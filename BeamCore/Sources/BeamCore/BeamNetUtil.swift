//
//  BeamNetUtil.swift
//  BeamCore
//
//  Created by . . on 9/22/25.
//

import Foundation
import Network

func short(_ t: NWInterface.InterfaceType) -> String {
    switch t {
    case .wifi: return "wifi"
    case .cellular: return "cell"
    case .wiredEthernet: return "wired"
    case .loopback: return "loop"
    case .other: return "other"
    @unknown default: return "?"
    }
}

func pathSummary(_ p: NWPath?) -> String {
    guard let p else { return "-" }
    var parts: [String] = []
    if p.usesInterfaceType(.wifi)          { parts.append("wifi") }
    if p.usesInterfaceType(.wiredEthernet) { parts.append("wired") }
    if p.usesInterfaceType(.cellular)      { parts.append("cell") }
    if p.usesInterfaceType(.other)         { parts.append("other") } // AWDL often shows as .other
    switch p.status {
    case .satisfied: parts.append("ok")
    case .unsatisfied: parts.append("no")
    case .requiresConnection: parts.append("need")
    @unknown default: break
    }
    if p.isExpensive   { parts.append("exp") }
    if p.isConstrained { parts.append("con") }
    let ifs = p.availableInterfaces.map { short($0.type) }.joined(separator: "|")
    if !ifs.isEmpty { parts.append("ifs=\(ifs)") }
    return parts.joined(separator: ",")
}

/// Safe, cross-version sockaddr renderer.
/// Fixes your compile errors by explicitly typing the raw buffer pointer.
func renderSockaddr(_ data: Data) -> String? {
    return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> String? in
        guard let base = raw.baseAddress else { return nil }
        // Inspect family from generic sockaddr
        let sa = base.assumingMemoryBound(to: sockaddr.self)
        switch Int32(sa.pointee.sa_family) {
        case AF_INET:
            guard raw.count >= MemoryLayout<sockaddr_in>.size else { return nil }
            let sin = base.assumingMemoryBound(to: sockaddr_in.self)
            var addr = sin.pointee.sin_addr
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            let ip = String(cString: buf)
            let port = Int(UInt16(bigEndian: sin.pointee.sin_port))
            return "\(ip):\(port)"

        case AF_INET6:
            guard raw.count >= MemoryLayout<sockaddr_in6>.size else { return nil }
            let sin6 = base.assumingMemoryBound(to: sockaddr_in6.self)
            var addr6 = sin6.pointee.sin6_addr
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &addr6, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
            let ip = String(cString: buf)
            let port = Int(UInt16(bigEndian: sin6.pointee.sin6_port))
            return "[\(ip)]:\(port)"

        default:
            return nil
        }
    }
}
