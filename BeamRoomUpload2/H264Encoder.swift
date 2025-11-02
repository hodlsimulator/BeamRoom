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
    private let queueKey = DispatchSpecificKey<UInt8>()

    private var pending: [(EncodedFrame) -> Void] = []
    private let pendingLock = NSLock()

    private var forceKeyframeNext = false

    init() {
        encodeQueue.setSpecific(key: queueKey, value: 1)
    }

    // MARK: Public

    func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopLocked()
        } else {
            encodeQueue.sync { self.stopLocked() }
        }
    }

    func encode(sampleBuffer sb: CMSampleBuffer, onEncoded: @escaping (EncodedFrame) -> Void) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)

        encodeQueue.async { [self] in
            if session == nil || width != w || height != h {
                makeSessionLocked(width: w, height: h)
                forceKeyframeNext = true
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
            var frameProps: CFDictionary?
            if forceKeyframeNext {
                frameProps = [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true] as CFDictionary
                forceKeyframeNext = false
            }

            let status = VTCompressionSessionEncodeFrame(
                sess,
                imageBuffer: pb,
                presentationTimeStamp: pts,
                duration: .invalid,
                frameProperties: frameProps,
                sourceFrameRefcon: nil,
                infoFlagsOut: &flags
            )

            if status != noErr {
                popAndFail()
            }
        }
    }

    // MARK: Internals (encodeQueue only)

    private func stopLocked() {
        if let s = session {
            VTCompressionSessionInvalidate(s)
            session = nil
        }
        prepared = false
        pending.removeAll()
    }

    private func makeSessionLocked(width: Int, height: Int) {
        precondition(DispatchQueue.getSpecific(key: queueKey) != nil, "must be on encodeQueue")
        stopLocked()

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
                // ReplayKit gives NV12; VT can accept it. Don’t force-convert.
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ] as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: vtOutputCallback,
            refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            compressionSessionOut: &s
        )

        guard let sess = s else { return }

        // Real-time, no reordering
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

        // Rate & cadence (robust over UDP):
        // ~1 Mbps target, peak ~1.5 Mbps, ~30 fps, IDR ≤2s
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 30 as CFTypeRef)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: 1_000_000))
        let limits: [NSNumber] = [1_500_000, 1] // bitsPerSecond, one-second window
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_DataRateLimits, value: limits as CFArray)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 30 as CFTypeRef)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 2 as CFTypeRef)

        // Profile
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)

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
        let notSync = (CMGetAttachment(sample, key: kCMSampleAttachmentKey_NotSync, attachmentModeOut: nil) as? NSNumber)?.boolValue ?? false
        let isKeyframe = !notSync

        var paramSets: H264Wire.ParamSets? = nil
        if isKeyframe, let f = CMSampleBufferGetFormatDescription(sample) {
            var count = 0
            var naluLen: Int32 = 0
            _ = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                f, parameterSetIndex: 0,
                parameterSetPointerOut: nil, parameterSetSizeOut: nil,
                parameterSetCountOut: &count, nalUnitHeaderLengthOut: &naluLen
            )
            var sps: [Data] = []
            var pps: [Data] = []
            for i in 0..<count {
                var p: UnsafePointer<UInt8>?
                var sz: Int = 0
                let st = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    f, parameterSetIndex: i,
                    parameterSetPointerOut: &p, parameterSetSizeOut: &sz,
                    parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil
                )
                if st == noErr, let pp = p, sz > 0 {
                    let d = Data(bytes: pp, count: sz)
                    if i == 0 { sps.append(d) } else { pps.append(d) }
                }
            }
            if !sps.isEmpty && !pps.isEmpty {
                paramSets = H264Wire.ParamSets(sps: sps, pps: pps)
            }
        }

        guard let bb = CMSampleBufferGetDataBuffer(sample) else {
            popAndFail(); return
        }
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPtr: UnsafeMutablePointer<Int8>?
        let st = CMBlockBufferGetDataPointer(
            bb, atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPtr
        )
        guard st == noErr, let p = dataPtr, totalLength > 0 else {
            popAndFail(); return
        }

        let avcc = Data(bytes: p, count: totalLength)
        let frame = EncodedFrame(avcc: avcc, isKeyframe: isKeyframe, paramSets: paramSets, width: width, height: height)

        pendingLock.lock()
        let cb = pending.isEmpty ? nil : pending.removeFirst()
        pendingLock.unlock()
        cb?(frame)
    }
}

// MARK: - VT callback

private func vtOutputCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard let me = outputCallbackRefCon.map({ Unmanaged<H264Encoder>.fromOpaque($0).takeUnretainedValue() }) else { return }
    guard status == noErr, let sb = sampleBuffer else {
        me.stop()
        return
    }
    me.onCompressed(sample: sb)
}
