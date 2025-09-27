//
//  H264Assembler.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  Reassembles fragmented H.264 access units (AVCC) and exposes param sets per keyframe.
//

import Foundation

public final class H264Assembler {
    public struct Unit {
        public let seq: UInt32
        public let isKeyframe: Bool
        public let width: Int
        public let height: Int
        public let paramSets: H264Wire.ParamSets? // only set on keyframes when present
        public let avccData: Data                // length-prefixed NAL units
    }

    private struct Partial {
        let createdAt = Date()
        let partCount: Int
        var got: [Bool]
        var buffers: [Int: Data] = [:]
        var cfg: H264Wire.ParamSets?
        let isKeyframe: Bool
        let width: Int
        let height: Int
    }

    private var map: [UInt32: Partial] = [:]
    private let maxAge: TimeInterval
    public init(maxAge: TimeInterval = 1.0) { self.maxAge = maxAge }

    public func ingest(datagram: Data) -> Unit? {
        guard let (hdr, bodyOffset) = H264Wire.parseHeaderBE(datagram) else { return nil }
        let totalParts = Int(hdr.partCount)
        let idx = Int(hdr.partIndex)
        guard totalParts > 0, idx < totalParts else { return nil }

        var start = bodyOffset
        var paramSets: H264Wire.ParamSets?
        if idx == 0, hdr.flags.contains(.hasParamSet), hdr.configBytes > 0 {
            let cfgLen = Int(hdr.configBytes)
            guard start + cfgLen <= datagram.count else { return nil }
            let cfgData = datagram.subdata(in: start..<(start+cfgLen))
            start += cfgLen
            paramSets = H264Wire.decodeParamSets(cfgData)
        }
        guard start <= datagram.count else { return nil }
        let frag = datagram.subdata(in: start..<datagram.count)

        // Garbage collect stale
        let now = Date()
        map = map.filter { now.timeIntervalSince($0.value.createdAt) <= maxAge }

        var p = map[hdr.seq] ?? Partial(partCount: totalParts,
                                        got: Array(repeating: false, count: totalParts),
                                        cfg: nil,
                                        isKeyframe: hdr.flags.contains(.keyframe),
                                        width: Int(hdr.width),
                                        height: Int(hdr.height))
        if idx == 0, let ps = paramSets { p.cfg = ps }
        if !p.got[idx] {
            p.buffers[idx] = frag
            p.got[idx] = true
        }
        map[hdr.seq] = p

        // Complete?
        if p.got.allSatisfy({ $0 }) {
            var out = Data()
            for i in 0..<p.partCount {
                guard let b = p.buffers[i] else { return nil }
                out.append(b)
            }
            map.removeValue(forKey: hdr.seq)
            return Unit(seq: hdr.seq,
                        isKeyframe: p.isKeyframe,
                        width: p.width,
                        height: p.height,
                        paramSets: p.cfg,
                        avccData: out)
        }
        return nil
    }

    public func reset() { map.removeAll() }
}
