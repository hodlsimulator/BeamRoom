//
//  H264Wire.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  Shared wire format helpers for H.264 over UDP (M4)
//

import Foundation

public enum H264Wire {
    // Magic BE: 'BMRV'
    public static let magic: UInt32 = 0x424D5256

    // Bit flags (u16)
    @frozen
    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        public static let keyframe    = Flags(rawValue: 1 << 0) // IDR
        public static let hasParamSet = Flags(rawValue: 1 << 1) // SPS/PPS present in part 0
    }

    // Fixed BE header (20 bytes)
    @frozen
    public struct Header: Equatable, Sendable {
        public var seq: UInt32
        public var partIndex: UInt16
        public var partCount: UInt16
        public var flags: Flags
        public var width: UInt16   // optional hint
        public var height: UInt16  // optional hint
        public var configBytes: UInt16 // only valid for partIndex==0 when hasParamSet set

        public init(seq: UInt32, partIndex: UInt16, partCount: UInt16, flags: Flags, width: UInt16, height: UInt16, configBytes: UInt16) {
            self.seq = seq; self.partIndex = partIndex; self.partCount = partCount
            self.flags = flags; self.width = width; self.height = height; self.configBytes = configBytes
        }
    }

    @frozen
    public struct ParamSets: Equatable, Sendable {
        public var sps: [Data]
        public var pps: [Data]
        public init(sps: [Data], pps: [Data]) { self.sps = sps; self.pps = pps }
    }

    // Simple param-set blob: [u8 spsCount][u8 ppsCount] then for each: [u16 len][bytes]...
    public static func encodeParamSets(_ ps: ParamSets) -> Data {
        var out = Data()
        out.append(UInt8(ps.sps.count))
        out.append(UInt8(ps.pps.count))
        for s in ps.sps { out.appendBE(UInt16(s.count)); out.append(s) }
        for p in ps.pps { out.appendBE(UInt16(p.count)); out.append(p) }
        return out
    }

    public static func decodeParamSets(_ data: Data) -> ParamSets? {
        guard data.count >= 2 else { return nil }
        let spsCount = Int(data[0]); let ppsCount = Int(data[1])
        var idx = 2
        var sps: [Data] = []; var pps: [Data] = []
        for _ in 0..<spsCount {
            guard idx + 2 <= data.count else { return nil }
            let len = Int(data.withUnsafeBytes { $0.load(fromByteOffset: idx, as: UInt16.self).bigEndian }); idx += 2
            guard idx + len <= data.count else { return nil }
            sps.append(data.subdata(in: idx..<(idx+len))); idx += len
        }
        for _ in 0..<ppsCount {
            guard idx + 2 <= data.count else { return nil }
            let len = Int(data.withUnsafeBytes { $0.load(fromByteOffset: idx, as: UInt16.self).bigEndian }); idx += 2
            guard idx + len <= data.count else { return nil }
            pps.append(data.subdata(in: idx..<(idx+len))); idx += len
        }
        return ParamSets(sps: sps, pps: pps)
    }

    public static let fixedHeaderBytes = 20

    public static func writeHeaderBE(_ h: Header) -> Data {
        var out = Data(capacity: fixedHeaderBytes)
        out.appendBE(magic)
        out.appendBE(h.seq)
        out.appendBE(h.partIndex)
        out.appendBE(h.partCount)
        out.appendBE(h.flags.rawValue)
        out.appendBE(h.width)
        out.appendBE(h.height)
        out.appendBE(h.configBytes)
        return out
    }

    // Returns (header, payloadStartOffset) or nil if invalid/not video
    public static func parseHeaderBE(_ data: Data) -> (Header, Int)? {
        guard data.count >= fixedHeaderBytes else { return nil }
        let m = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).bigEndian }
        guard m == magic else { return nil }
        let seq       = data.withUnsafeBytes { $0.load(fromByteOffset: 4,  as: UInt32.self).bigEndian }
        let partIndex = data.withUnsafeBytes { $0.load(fromByteOffset: 8,  as: UInt16.self).bigEndian }
        let partCount = data.withUnsafeBytes { $0.load(fromByteOffset: 10, as: UInt16.self).bigEndian }
        let flagsRaw  = data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt16.self).bigEndian }
        let width     = data.withUnsafeBytes { $0.load(fromByteOffset: 14, as: UInt16.self).bigEndian }
        let height    = data.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt16.self).bigEndian }
        let cfgBytes  = data.withUnsafeBytes { $0.load(fromByteOffset: 18, as: UInt16.self).bigEndian }
        return (Header(seq: seq, partIndex: partIndex, partCount: partCount, flags: Flags(rawValue: flagsRaw), width: width, height: height, configBytes: cfgBytes), fixedHeaderBytes)
    }
}

// NOTE: No Data.appendBE here — we use the shared helper in Data+BigEndian.swift.
