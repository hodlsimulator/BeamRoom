//
//  Data+BigEndian.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  Safe helper to append integers in big-endian without shadowing withUnsafeBytes.
//

import Foundation

extension Data {
    /// Append any fixed-width integer in **big-endian** byte order.
    /// Uses the global `Swift.withUnsafeBytes(of:_:)` to avoid the instance method shadow.
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            self.append(base.bindMemory(to: UInt8.self, capacity: rawBuf.count), count: rawBuf.count)
        }
    }
}
