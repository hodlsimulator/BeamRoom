//
//  H264Assembler.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  Reassembles fragmented M4 (H.264 over UDP) frames into AVCC access units.
//

import Foundation

public final class H264Assembler {

    public struct Unit {
        public let seq: UInt32
        public let isKeyframe: Bool
        public let width: Int
        public let height: Int
        public let paramSets: H264Wire.ParamSets?   // present only on keyframes
        public let avccData: Data                  // concatenated AVCC payload
    }

    private struct Partial {
        let createdAt = Date()
        let totalParts: Int
        var received: [Bool]
        var chunks: [Int: Data] = [:]
        var cfg: H264Wire.ParamSets?
        let keyframe: Bool
        let width: Int
        let height: Int
    }

    private var partials: [UInt32: Partial] = [:]
    private let maxAge: TimeInterval

    public init(maxAge: TimeInterval = 1.0) {
        self.maxAge = maxAge
    }

    /// Ingest one UDP datagram. Returns a complete Unit when all parts for `seq` have arrived.
    public func ingest(datagram: Data) -> Unit? {
        guard let (hdr, bodyOffset) = H264Wire.parseHeaderBE(datagram) else { return nil }

        let seq = hdr.seq
        let count = Int(hdr.partCount)
        let idx = Int(hdr.partIndex)
        guard count > 0, idx >= 0, idx < count else { return nil }

        var start = bodyOffset

        // Optional param sets are only in part 0 when flagged.
        var cfg: H264Wire.ParamSets?
        if idx == 0, hdr.flags.contains(.hasParamSet), hdr.configBytes > 0 {
            let cfgLen = Int(hdr.configBytes)
            guard start + cfgLen <= datagram.count else { return nil }
            let cfgBlob = datagram.subdata(in: start..<(start + cfgLen))
            start += cfgLen
            cfg = H264Wire.decodeParamSets(cfgBlob)
        }

        guard start <= datagram.count else { return nil }
        let payload = datagram.subdata(in: start..<datagram.count)

        // Upsert partial frame
        var p: Partial
        if let existing = partials[seq], existing.totalParts == count {
            p = existing
        } else {
            // start a fresh container (or reset if partCount changed)
            p = Partial(
                totalParts: count,
                received: Array(repeating: false, count: count),
                chunks: [:],
                cfg: nil,
                keyframe: hdr.flags.contains(.keyframe),
                width: Int(hdr.width),
                height: Int(hdr.height)
            )
        }

        p.received[idx] = true
        p.chunks[idx] = payload
        if idx == 0, let cfg { p.cfg = cfg }

        partials[seq] = p

        // Completed?
        if p.received.allSatisfy({ $0 }) {
            var data = Data()
            data.reserveCapacity(p.chunks.values.reduce(0) { $0 + $1.count })
            for i in 0..<p.totalParts {
                if let d = p.chunks[i] { data.append(d) } else { return nil } // shouldn’t happen
            }

            partials.removeValue(forKey: seq)
            pruneStale()

            return Unit(
                seq: seq,
                isKeyframe: p.keyframe,
                width: p.width,
                height: p.height,
                paramSets: p.cfg,
                avccData: data
            )
        }

        pruneStale()
        return nil
    }

    /// Clear any incomplete frames older than `maxAge`.
    public func reset() {
        partials.removeAll()
    }

    private func pruneStale() {
        let now = Date()
        partials = partials.filter { now.timeIntervalSince($0.value.createdAt) < maxAge }
    }
}
