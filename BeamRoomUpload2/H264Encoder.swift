//
//  H264Encoder.swift
//  BeamRoomHost
//
//  Created by . . on 10/31/25.
//

import Foundation
@preconcurrency import Dispatch
import CoreMedia
import CoreVideo
import VideoToolbox
import BeamCore

final class H264Encoder: @unchecked Sendable {

    struct EncodedFrame {
        let avcc: Data
        let isKeyframe: Bool
        let paramSets: H264Wire.ParamSets?
        let width: Int
        let height: Int
    }

    private var session: VTCompressionSession?
    private var width: Int = 0
    private var height: Int = 0
    private var prepared = false

    private let encodeQueue = DispatchQueue(label: "beam.upload2.h264.encoder", qos: .userInitiated)
    private var pending: [(EncodedFrame) -> Void] = []
    private let pendingLock = NSLock()

    func stop() {
        encodeQueue.sync {
            if let s = session {
                VTCompressionSessionInvalidate(s)
                session = nil
            }
            prepared = false
            pending.removeAll()
        }
    }

    func encode(sampleBuffer sb: CMSampleBuffer, onEncoded: @escaping (EncodedFrame) -> Void) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)

        encodeQueue.async { [self] in
            if session == nil || width != w || height != h {
                makeSession(width: w, height: h)
            }
            guard let sess = session else { return }
            if !prepared {
                VTCompressionSessionPrepareToEncodeFrames(sess)
                prepared = true
            }

            pendingLock.lock()
            pending.append(onEncoded)
            pendingLock.unlock()

            var flags = VTEncodeInfoFlags()
            let status = VTCompressionSessionEncodeFrame(
                sess,
                imageBuffer: pb,
                presentationTimeStamp: pts,
                duration: .invalid,
                frameProperties: nil,
                sourceFrameRefcon: nil,
                infoFlagsOut: &flags
            )
            if status != noErr {
                popAndFail()
            }
        }
    }

    private func makeSession(width: Int, height: Int) {
        stop()
        self.width = width
        self.height = height

        var s: VTCompressionSession?
        VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
            ] as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: vtOutputCallback,
            refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            compressionSessionOut: &s
        )
        guard let sess = s else { return }

        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 60 as CFTypeRef)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 60 as CFTypeRef)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: 2_000_000))

        session = sess
        prepared = false
    }

    private func popAndFail() {
        pendingLock.lock()
        let cb = pending.isEmpty ? nil : pending.removeFirst()
        pendingLock.unlock()
        if let cb {
            cb(EncodedFrame(avcc: Data(), isKeyframe: false, paramSets: nil, width: 0, height: 0))
        }
    }

    func onCompressed(sample: CMSampleBuffer) {
        // Keyframe?
        let notSync = (CMGetAttachment(sample, key: kCMSampleAttachmentKey_NotSync, attachmentModeOut: nil) as? NSNumber)?.boolValue ?? false
        let isKeyframe = !notSync

        // Param sets (SPS/PPS) on keyframes
        var ps: H264Wire.ParamSets? = nil
        if isKeyframe, let f = CMSampleBufferGetFormatDescription(sample) {
            var count: Int = 0
            var naluLen: Int32 = 0
            let _ = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                f, parameterSetIndex: 0,
                parameterSetPointerOut: nil, parameterSetSizeOut: nil,
                parameterSetCountOut: &count, nalUnitHeaderLengthOut: &naluLen
            )
            var spsList: [Data] = []
            var ppsList: [Data] = []
            for i in 0..<max(count, 2) {
                var p: UnsafePointer<UInt8>? = nil
                var sz: Int = 0
                let st = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    f, parameterSetIndex: i,
                    parameterSetPointerOut: &p, parameterSetSizeOut: &sz,
                    parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil
                )
                if st == noErr, let pp = p, sz > 0 {
                    let d = Data(bytes: pp, count: sz)
                    if i == 0 { spsList.append(d) } else { ppsList.append(d) }
                }
            }
            if !spsList.isEmpty && !ppsList.isEmpty {
                ps = H264Wire.ParamSets(sps: spsList, pps: ppsList)
            }
        }

        // AVCC payload
        guard let bb = CMSampleBufferGetDataBuffer(sample) else { popAndFail(); return }
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPtr: UnsafeMutablePointer<Int8>?
        let st = CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPtr)
        guard st == noErr, let p = dataPtr, totalLength > 0 else { popAndFail(); return }

        let avcc = Data(bytes: p, count: totalLength)
        let frame = EncodedFrame(avcc: avcc, isKeyframe: isKeyframe, paramSets: ps, width: width, height: height)

        pendingLock.lock()
        let cb = pending.isEmpty ? nil : pending.removeFirst()
        pendingLock.unlock()
        cb?(frame)
    }
}

// VT callback
private func vtOutputCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard status == noErr, let sb = sampleBuffer else {
        if let me = outputCallbackRefCon.map({ Unmanaged<H264Encoder>.fromOpaque($0).takeUnretainedValue() }) {
            me.stop()
        }
        return
    }
    let me = Unmanaged<H264Encoder>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
    me.onCompressed(sample: sb)
}
