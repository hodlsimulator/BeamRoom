//
//  H264Encoder.swift
//  BeamRoomHost
//
//  Created by . . on 9/27/25.
//
// VideoToolbox H.264 encoder for ReplayKit frames + AVCC helpers and wire packetiser.
//

import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo
import OSLog
import BeamCore

final class H264Encoder {

    struct Encoded {
        let sample: CMSampleBuffer
        let isKeyframe: Bool
        let paramSets: H264Wire.ParamSets? // present on keyframes
        let width: Int
        let height: Int
    }

    private let log = Logger(subsystem: BeamConfig.subsystemExt, category: "h264-enc")
    private var session: VTCompressionSession?
    private var width: Int = 0
    private var height: Int = 0

    private let targetBitrate: Int
    private let fps: Int
    private let keyframeIntervalSeconds: Int

    init(targetBitrate: Int = 1_200_000, fps: Int = 15, keyframeIntervalSeconds: Int = 2) {
        self.targetBitrate = targetBitrate
        self.fps = fps
        self.keyframeIntervalSeconds = keyframeIntervalSeconds
    }

    deinit { invalidate() }

    func invalidate() {
        if let s = session {
            VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(s)
        }
        session = nil
        width = 0; height = 0
    }

    // MARK: - Encode

    func encode(_ sb: CMSampleBuffer, onEncoded: @escaping (Encoded) -> Void) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)

        if session == nil || w != width || h != height {
            createSession(width: w, height: h)
        }
        guard let sess = session else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        var info = VTEncodeInfoFlags()

        let status = VTCompressionSessionEncodeFrame(
            sess,
            imageBuffer: pb,
            presentationTimeStamp: pts,
            duration: .invalid,
            frameProperties: nil,
            infoFlagsOut: &info
        ) { [weak self] status, _, sampleBuffer in
            guard status == noErr, let self, let sampleBuffer else {
                if status != noErr {
                    self?.log.error("Encode callback status=\(status)")
                }
                return
            }

            // Keyframe?
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as? [[CFString: Any]]
            let notSync = (attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
            let isKey = !notSync

            // Param sets (SPS/PPS) for keyframes
            var psOut: H264Wire.ParamSets?
            var outW = w, outH = h
            if let fd = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let dims = CMVideoFormatDescriptionGetDimensions(fd)
                if dims.width > 0 && dims.height > 0 {
                    outW = Int(dims.width)
                    outH = Int(dims.height)
                }

                if isKey {
                    var spsPtr: UnsafePointer<UInt8>?
                    var spsSize = 0
                    var spsCount = 0
                    var ppsPtr: UnsafePointer<UInt8>?
                    var ppsSize = 0
                    var ppsCount = 0

                    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                        fd, parameterSetIndex: 0,
                        parameterSetPointerOut: &spsPtr, parameterSetSizeOut: &spsSize,
                        parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: nil
                    )
                    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                        fd, parameterSetIndex: 1,
                        parameterSetPointerOut: &ppsPtr, parameterSetSizeOut: &ppsSize,
                        parameterSetCountOut: &ppsCount, nalUnitHeaderLengthOut: nil
                    )

                    var spsArr: [Data] = []
                    var ppsArr: [Data] = []
                    if let p = spsPtr, spsSize > 0 { spsArr.append(Data(bytes: p, count: spsSize)) }
                    if let p = ppsPtr, ppsSize > 0 { ppsArr.append(Data(bytes: p, count: ppsSize)) }
                    if !spsArr.isEmpty && !ppsArr.isEmpty {
                        psOut = H264Wire.ParamSets(sps: spsArr, pps: ppsArr)
                    }
                }
            }

            onEncoded(Encoded(sample: sampleBuffer, isKeyframe: isKey, paramSets: psOut, width: outW, height: outH))
        }

        if status != noErr {
            log.error("Encode submit failed status=\(status)")
        }
    }

    // MARK: - Session

    private func createSession(width w: Int, height h: Int) {
        invalidate()

        var sess: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(w),
            height: Int32(h),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &sess
        )

        guard status == noErr, let s = sess else {
            log.error("VTCompressionSessionCreate failed status=\(status)")
            return
        }

        width = w; height = h
        session = s

        // Real-time, no B-frames, baseline profile for low latency & broad support.
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)

        // Bitrate / rate control
        let br = targetBitrate as CFNumber
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: br)
        // Data rate limits: [bytesPerSecond, oneSecond]
        let bytesPerSecond = max(1, targetBitrate / 8) as CFNumber
        let oneSec = 1 as CFNumber
        let limits = [bytesPerSecond, oneSec] as CFArray
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_DataRateLimits, value: limits)

        // Frame rate & keyframe interval
        let fpsNum = fps as CFNumber
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fpsNum)
        let maxKeyInterval = max(1, fps * keyframeIntervalSeconds) as CFNumber
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: maxKeyInterval)

        let prep = VTCompressionSessionPrepareToEncodeFrames(s)
        if prep != noErr {
            log.error("PrepareToEncodeFrames failed status=\(prep)")
        } else {
            log.info("H.264 session ready \(w)x\(h) @\(self.fps)fps, \(self.targetBitrate) bps")
        }
    }

    // Optional: force a keyframe on next encode() call
    func requestKeyframe() {
        guard let s = session else { return }
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ForceKeyFrame, value: kCFBooleanTrue)
    }

    // MARK: - AVCC extraction

    /// Returns the frame's AVCC (length-prefixed) NAL units as a single Data blob.
    static func avccData(from sample: CMSampleBuffer) -> Data? {
        guard let db = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let len = CMBlockBufferGetDataLength(db)
        guard len > 0 else { return Data() }
        var out = Data(count: len)
        let status = out.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(db, atOffset: 0, dataLength: len, destination: base)
        }
        return (status == noErr) ? out : nil
    }

    // MARK: - Wire packetiser (M4)

    /// Fragment a single encoded frame into BMRV datagrams (≤ `mtu` each).
    /// Increments `seq` (frame sequence) once per frame.
    static func packetise(_ e: Encoded, seq: inout UInt32, mtu: Int = 1200) -> [Data] {
        guard let payload = avccData(from: e.sample), !payload.isEmpty else { return [] }

        let cfgData: Data = (e.isKeyframe && e.paramSets != nil) ? H264Wire.encodeParamSets(e.paramSets!) : Data()
        var flags = H264Wire.Flags()
        if e.isKeyframe { flags.insert(.keyframe) }
        if !cfgData.isEmpty { flags.insert(.hasParamSet) }

        let fixed = H264Wire.fixedHeaderBytes
        let firstBudget = mtu - fixed - cfgData.count
        let restBudget  = mtu - fixed
        guard firstBudget > 0 && restBudget > 0 else { return [] }

        let total = payload.count
        var parts = 1
        if total > firstBudget {
            let remain = total - firstBudget
            let extra = (remain + (restBudget - 1)) / restBudget
            parts = 1 + max(0, extra)
        }

        let widthU16  = UInt16(clamping: e.width)
        let heightU16 = UInt16(clamping: e.height)
        var out: [Data] = []
        out.reserveCapacity(parts)

        var offset = 0
        for idx in 0..<parts {
            let budget = (idx == 0) ? firstBudget : restBudget
            let remain = total - offset
            let take   = min(budget, remain)

            var header = H264Wire.Header(
                seq: seq,
                partIndex: UInt16(idx),
                partCount: UInt16(parts),
                flags: flags,
                width: widthU16,
                height: heightU16,
                configBytes: (idx == 0) ? UInt16(cfgData.count) : 0
            )
            var datagram = H264Wire.writeHeaderBE(header)
            if idx == 0 && !cfgData.isEmpty { datagram.append(cfgData) }
            datagram.append(payload.subdata(in: offset..<(offset + take)))
            out.append(datagram)

            offset += take
        }

        seq &+= 1
        return out
    }
}

// Small helper so UInt16(clamping:) is available for Int inputs.
private extension UInt16 {
    init(clamping value: Int) {
        if value < 0 { self = 0 }
        else if value > Int(UInt16.max) { self = .max }
        else { self = UInt16(value) }
    }
}
