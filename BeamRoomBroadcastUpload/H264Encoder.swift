//
//  H264Encoder.swift
//  BeamRoomHost
//
//  Created by . . on 9/27/25.
//
//  VideoToolbox H.264 encoder for ReplayKit frames.
//  Produces AVCC (length-prefixed) samples and exposes SPS/PPS for keyframes.
//

/*
import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox
import BeamCore

final class H264Encoder {

    struct Encoded {
        let sample: CMSampleBuffer
        let width: Int
        let height: Int
        let isKeyframe: Bool
        let paramSets: H264Wire.ParamSets?
    }

    private var session: VTCompressionSession?
    private var width: Int = 0
    private var height: Int = 0

    func invalidate() {
        if let s = session {
            VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(s)
        }
        session = nil
    }

    func encode(_ sb: CMSampleBuffer, completion: @escaping (Encoded) -> Void) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }

        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)

        if session == nil || w != width || h != height {
            makeSession(width: w, height: h)
        }
        guard let sess = session else { return }

        // Presentation timestamp (fallback to host time if missing)
        var pts = CMSampleBufferGetPresentationTimeStamp(sb)
        if !pts.isValid {
            pts = CMClockGetTime(CMClockGetHostTimeClock())
        }

        // Box the completion so we can get it back in the VT callback
        let box = CallbackBox(done: completion)

        let status = VTCompressionSessionEncodeFrame(
            sess,
            imageBuffer: pb,
            presentationTimeStamp: pts,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: Unmanaged.passRetained(box).toOpaque(),
            infoFlagsOut: nil
        )

        if status != noErr {
            // Drop the frame on error
            return
        }
    }

    private func makeSession(width w: Int, height h: Int) {
        invalidate()

        width = w; height = h

        var s: VTCompressionSession?
        let st = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(w),
            height: Int32(h),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: kCFAllocatorDefault,
            outputCallback: { _, sourceFrameRefCon, status, _, sampleBuffer in
                guard status == noErr, let sb = sampleBuffer else {
                    // Balance the retain even if encoding failed before we could unpack
                    if let sref = sourceFrameRefCon {
                        Unmanaged<CallbackBox>.fromOpaque(sref).release()
                    }
                    return
                }
                guard let sref = sourceFrameRefCon else { return }
                let box = Unmanaged<CallbackBox>.fromOpaque(sref).takeRetainedValue()

                // Keyframe?
                var isKey = true
                if let array = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]],
                   let first = array.first,
                   let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
                    isKey = !notSync
                }

                // Dimensions + parameter sets
                guard let fmt = CMSampleBufferGetFormatDescription(sb) else { return }
                let dims = CMVideoFormatDescriptionGetDimensions(fmt)
                let outW = Int(dims.width), outH = Int(dims.height)
                let ps = isKey ? H264Encoder.extractParamSets(from: fmt) : nil

                let out = Encoded(sample: sb, width: outW, height: outH, isKeyframe: isKey, paramSets: ps)
                box.done(out)
            },
            refcon: nil,
            compressionSessionOut: &s
        )

        if st != noErr || s == nil { return }
        guard let sess = s else { return }

        // Realtime, low-latency settings
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 2.0)) // 2s GOP
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: 30))

        // Heuristic bitrate: ~0.09 bits/pixel*fps
        let bps = Int(Double(w * h) * 0.09 * 30.0)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bps))
        let dataRate: [NSNumber] = [NSNumber(value: bps / 2), 1] // bytes per second, duration seconds
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_DataRateLimits, value: dataRate as CFArray)

        _ = VTCompressionSessionPrepareToEncodeFrames(sess)
        session = sess
    }

    // MARK: - Helpers

    private final class CallbackBox {
        let done: (Encoded) -> Void
        init(done: @escaping (Encoded) -> Void) { self.done = done }
    }

    static func avccData(from sb: CMSampleBuffer) -> Data? {
        guard let bb = CMSampleBufferGetDataBuffer(sb) else { return nil }

        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let st = CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard st == kCMBlockBufferNoErr, totalLength > 0, let base = dataPointer else { return nil }

        let raw = Data(bytes: base, count: totalLength)

        // If it looks like Annex-B (start codes), convert to AVCC
        if raw.count >= 4 && raw.prefix(4) == Data([0,0,0,1]) {
            return annexBtoAVCC(raw)
        }
        return raw
    }

    private static func annexBtoAVCC(_ annexB: Data) -> Data? {
        var out = Data()
        let bytes = [UInt8](annexB)
        let end = bytes.count

        func nextStartCode(_ from: Int) -> Int? {
            var i = from
            while i + 3 < end {
                if bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 0 && bytes[i+3] == 1 { return i }
                i += 1
            }
            return nil
        }

        var pos = 0
        while let sc = nextStartCode(pos) {
            let payloadStart = sc + 4
            let next = nextStartCode(payloadStart) ?? end
            let len = next - payloadStart
            if len > 0 {
                // Write 4-byte big-endian length without unsafe pointer APIs
                let be = UInt32(len).bigEndian
                out.append(UInt8(truncatingIfNeeded: be >> 24))
                out.append(UInt8(truncatingIfNeeded: be >> 16))
                out.append(UInt8(truncatingIfNeeded: be >> 8))
                out.append(UInt8(truncatingIfNeeded: be))

                out.append(contentsOf: bytes[payloadStart..<next])
            }
            pos = next
            if pos >= end { break }
        }
        return out.isEmpty ? nil : out
    }

    private static func extractParamSets(from fmt: CMFormatDescription) -> H264Wire.ParamSets? {
        guard CMFormatDescriptionGetMediaSubType(fmt) == kCMVideoCodecType_H264 else { return nil }

        // Ask for count/header once (index 0); then iterate 0..<count and classify by NAL type.
        var count: Int = 0
        var nalLen: Int32 = 0
        var tmpPtr: UnsafePointer<UInt8>?
        var tmpSize: Int = 0
        let status0 = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, parameterSetIndex: 0, parameterSetPointerOut: &tmpPtr, parameterSetSizeOut: &tmpSize, parameterSetCountOut: &count, nalUnitHeaderLengthOut: &nalLen)
        guard status0 == noErr else { return nil }

        var sps: [Data] = []
        var pps: [Data] = []

        for i in 0..<count {
            var p: UnsafePointer<UInt8>?
            var s: Int = 0
            let st = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &s, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            if st == noErr, let p, s > 0 {
                let d = Data(bytes: p, count: s)
                if let first = d.first {
                    let nalType = first & 0x1F
                    if nalType == 7 { sps.append(d) }        // SPS
                    else if nalType == 8 { pps.append(d) }   // PPS
                }
            }
        }

        if sps.isEmpty || pps.isEmpty { return nil }
        return H264Wire.ParamSets(sps: sps, pps: pps)
    }
}
*/
