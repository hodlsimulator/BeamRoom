//
//  H264Decoder.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  VideoToolbox H.264 decoder for AVCC samples → CGImage
//

import Foundation
import VideoToolbox
import CoreImage
import CoreMedia
import CoreGraphics

public final class H264Decoder {
    private var formatDesc: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private let ci = CIContext(options: nil)

    public init() {}

    deinit { invalidate() }

    public func invalidate() {
        if let s = session {
            VTDecompressionSessionInvalidate(s)
        }
        session = nil
        formatDesc = nil
    }

    private func ensureFormat(paramSets: H264Wire.ParamSets?, width: Int?, height: Int?) -> Bool {
        if let ps = paramSets, !ps.sps.isEmpty, !ps.pps.isEmpty {
            var parameterSetPointers: [UnsafePointer<UInt8>?] = []
            var parameterSetSizes: [Int] = []
            for s in ps.sps {
                s.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
                    parameterSetPointers.append(p.bindMemory(to: UInt8.self).baseAddress)
                    parameterSetSizes.append(s.count)
                }
            }
            for p in ps.pps {
                p.withUnsafeBytes { (q: UnsafeRawBufferPointer) in
                    parameterSetPointers.append(q.bindMemory(to: UInt8.self).baseAddress)
                    parameterSetSizes.append(p.count)
                }
            }
            let count = parameterSetPointers.count
            var fmt: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault,
                                                                             parameterSetCount: count,
                                                                             parameterSetPointers: &parameterSetPointers,
                                                                             parameterSetSizes: &parameterSetSizes,
                                                                             nalUnitHeaderLength: 4,
                                                                             formatDescriptionOut: &fmt)
            if status == noErr, let f = fmt {
                formatDesc = f
                // Recreate session
                if let s = session { VTDecompressionSessionInvalidate(s) }
                var callback = VTDecompressionOutputCallbackRecord()
                callback.decompressionOutputCallback = nil
                callback.decompressionOutputRefCon = nil
                let attrs: [CFString: Any] = [
                    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                ]
                var newSession: VTDecompressionSession?
                let st2 = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                       formatDescription: f,
                                                       decoderSpecification: nil,
                                                       imageBufferAttributes: attrs as CFDictionary,
                                                       outputCallback: &callback,
                                                       decompressionSessionOut: &newSession)
                if st2 == noErr { session = newSession }
            }
        }
        return session != nil
    }

    public func decode(avcc sampleData: Data,
                       paramSets: H264Wire.ParamSets?,
                       completion: @escaping (CGImage?) -> Void)
    {
        _ = ensureFormat(paramSets: paramSets, width: nil, height: nil)
        guard let fmt = formatDesc, let sess = session else {
            completion(nil); return
        }

        var block: CMBlockBuffer?
        var data = sampleData // local mutable
        let stB = data.withUnsafeMutableBytes { raw -> OSStatus in
            CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                               memoryBlock: raw.baseAddress,
                                               blockLength: raw.count,
                                               blockAllocator: kCFAllocatorNull,
                                               customBlockSource: nil,
                                               offsetToData: 0,
                                               dataLength: raw.count,
                                               flags: 0,
                                               blockBufferOut: &block)
        }
        guard stB == noErr, let bb = block else { completion(nil); return }

        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime.invalid,
                                        presentationTimeStamp: CMTime.invalid,
                                        decodeTimeStamp: CMTime.invalid)
        let stS = CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                       dataBuffer: bb,
                                       dataReady: true,
                                       makeDataReadyCallback: nil,
                                       refcon: nil,
                                       formatDescription: fmt,
                                       sampleCount: 1,
                                       sampleTimingEntryCount: 1,
                                       sampleTimingArray: &timing,
                                       sampleSizeEntryCount: 0,
                                       sampleSizeArray: nil,
                                       sampleBufferOut: &sample)
        guard stS == noErr, let sb = sample else { completion(nil); return }

        var imgOut: CGImage?

        let flags: VTDecodeFrameFlags = []
        var outFlags = VTDecodeInfoFlags()
        let stD = VTDecompressionSessionDecodeFrame(sess, sampleBuffer: sb,
                                                    flags: flags,
                                                    frameRefcon: nil,
                                                    infoFlagsOut: &outFlags) { _, _, status, infoFlags, imageBuffer, _, _ in
            guard status == noErr, let pb = imageBuffer else { return }
            let ciImage = CIImage(cvPixelBuffer: pb)
            let cs = CGColorSpaceCreateDeviceRGB()
            imgOut = self.ci.createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: cs)
        }

        if stD != noErr {
            completion(nil)
        } else {
            completion(imgOut)
        }
    }
}
