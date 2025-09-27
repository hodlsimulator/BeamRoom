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
import CoreVideo

public final class H264Decoder {
    private var formatDesc: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private let ci = CIContext(options: nil)

    // Thread-safe state (no actor isolation warnings)
    private let stateQueue = DispatchQueue(label: "com.conornolan.beamroom.h264decoder.state")

    // Box the completion to avoid Sendable diagnostics when hopping queues.
    private final class CompletionBox: @unchecked Sendable {
        let invoke: (CGImage?) -> Void
        init(_ body: @escaping (CGImage?) -> Void) { self.invoke = body }
    }
    private var pending: [CompletionBox] = []

    public init() {}

    deinit { invalidate() }

    // MARK: - Lifecycle

    public func invalidate() {
        var s: VTDecompressionSession?
        stateQueue.sync {
            s = self.session
            self.session = nil
            self.formatDesc = nil
            self.pending.removeAll()
        }
        if let s { VTDecompressionSessionInvalidate(s) }
    }

    // MARK: - Format / Session

    /// Ensures a VTDecompressionSession exists. Requires SPS/PPS on first call.
    private func ensureFormat(paramSets: H264Wire.ParamSets?, width: Int?, height: Int?) -> Bool {
        // If we already have a session, we're good.
        var haveSession = false
        stateQueue.sync { haveSession = (self.session != nil) }
        if haveSession { return true }

        // Need param sets (from a keyframe) to create the session.
        guard let ps = paramSets, !ps.sps.isEmpty, !ps.pps.isEmpty else { return false }

        // Build non-optional pointer arrays
        var paramPtrs: [UnsafePointer<UInt8>] = []
        var paramSizes: [Int] = []

        for s in ps.sps where !s.isEmpty {
            s.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                if let base = raw.bindMemory(to: UInt8.self).baseAddress {
                    paramPtrs.append(base)
                    paramSizes.append(s.count)
                }
            }
        }
        for p in ps.pps where !p.isEmpty {
            p.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                if let base = raw.bindMemory(to: UInt8.self).baseAddress {
                    paramPtrs.append(base)
                    paramSizes.append(p.count)
                }
            }
        }
        guard !paramPtrs.isEmpty, paramPtrs.count == paramSizes.count else { return false }

        var fmt: CMVideoFormatDescription?
        let status: OSStatus = paramPtrs.withUnsafeBufferPointer { ptrs in
            paramSizes.withUnsafeBufferPointer { sizes in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: ptrs.count,
                    parameterSetPointers: ptrs.baseAddress!,
                    parameterSetSizes: sizes.baseAddress!,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &fmt
                )
            }
        }
        guard status == noErr, let f = fmt else { return false }

        // Create a decompression session using the C-callback API.
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refCon, _, status, _, imageBuffer, _, _ in
                let me = Unmanaged<H264Decoder>.fromOpaque(refCon!).takeUnretainedValue()
                guard status == noErr, let pb = imageBuffer else {
                    me.deliver(nil)
                    return
                }
                me.output(pixelBuffer: pb)
            },
            decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        var newSession: VTDecompressionSession?
        let st2 = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: f,
            decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &newSession
        )
        guard st2 == noErr, let sess = newSession else { return false }

        stateQueue.sync {
            self.formatDesc = f
            self.session = sess
        }
        return true
    }

    private func output(pixelBuffer pb: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pb)
        let cs = CGColorSpaceCreateDeviceRGB()
        let cg = ci.createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: cs)
        deliver(cg)
    }

    /// Pop the next completion under the state lock, then invoke it on the main queue,
    /// passing only a boxed callback across the hop to avoid Sendable warnings.
    private func deliver(_ image: CGImage?) {
        var box: CompletionBox?
        stateQueue.sync {
            if !self.pending.isEmpty {
                box = self.pending.removeFirst()
            }
        }
        guard let box else { return }
        DispatchQueue.main.async {
            box.invoke(image)
        }
    }

    // MARK: - Decode

    public func decode(avcc sampleData: Data,
                       paramSets: H264Wire.ParamSets?,
                       completion: @escaping (CGImage?) -> Void)
    {
        guard ensureFormat(paramSets: paramSets, width: nil, height: nil) else {
            completion(nil); return
        }

        var fmt: CMVideoFormatDescription?
        var sess: VTDecompressionSession?
        stateQueue.sync { fmt = self.formatDesc; sess = self.session }
        guard let fmt, let sess else { completion(nil); return }

        // Own the memory inside the CMBlockBuffer (don’t alias Data’s buffer).
        var block: CMBlockBuffer?
        let stBlock = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: sampleData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: sampleData.count,
            flags: 0,
            blockBufferOut: &block
        )
        guard stBlock == noErr, let bb = block else { completion(nil); return }

        _ = sampleData.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                CMBlockBufferReplaceDataBytes(
                    with: base,
                    blockBuffer: bb,
                    offsetIntoDestination: 0,
                    dataLength: sampleData.count
                )
            }
        }

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

        // Queue the completion before requesting decode (FIFO).
        stateQueue.sync { self.pending.append(CompletionBox(completion)) }

        var outFlags = VTDecodeInfoFlags()
        let flags: VTDecodeFrameFlags = []

        // Output arrives via the session's callback.
        let stD = VTDecompressionSessionDecodeFrame(
            sess,
            sampleBuffer: sb,
            flags: flags,
            frameRefcon: nil,
            infoFlagsOut: &outFlags
        )

        if stD != noErr {
            // Deliver failure for this frame
            deliver(nil)
        }
    }
}
