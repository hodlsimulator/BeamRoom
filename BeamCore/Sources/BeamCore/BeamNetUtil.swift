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

/// sockaddr renderer with explicit UnsafeRawBufferPointer typing (fixes Swift 6 generics errors)
func renderSockaddr(_ data: Data) -> String? {
    return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> String? in
        guard let base = raw.baseAddress else { return nil }
        let sa = base.assumingMemoryBound(to: sockaddr.self)
        switch Int32(sa.pointee.sa_family) {
        case AF_INET:
            guard raw.count >= MemoryLayout<sockaddr_in>.size else { return nil }
            let sin = base.assumingMemoryBound(to: sockaddr_in.self)
            var addr = sin.pointee.sin_addr
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            let ip = String(cString: buf)
            let port = UInt16(bigEndian: sin.pointee.sin_port)
            return "\(ip):\(port)"
        case AF_INET6:
            guard raw.count >= MemoryLayout<sockaddr_in6>.size else { return nil }
            let sin6 = base.assumingMemoryBound(to: sockaddr_in6.self)
            var addr6 = sin6.pointee.sin6_addr
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &addr6, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
            let ip = String(cString: buf)
            let port = UInt16(bigEndian: sin6.pointee.sin6_port)
            return "[\(ip)]:\(port)"
        default:
            return nil
        }
    }
}

/// True for RFC1918 IPv4
func isPrivateIPv4(_ ip: String) -> Bool {
    if ip.hasPrefix("10.") { return true }
    if ip.hasPrefix("192.168.") { return true }
    if ip.hasPrefix("172.") {
        let comps = ip.split(separator: ".")
        if comps.count > 1, let second = Int(comps[1]), (16...31).contains(second) { return true }
    }
    return false
}

/// Parse a sockaddr Data into (host, port, isIPv4)
func parseSockaddrHostPort(_ data: Data) -> (host: String, port: UInt16, isIPv4: Bool)? {
    return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> (String, UInt16, Bool)? in
        guard let base = raw.baseAddress else { return nil }
        let fam = base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family
        switch Int32(fam) {
        case AF_INET:
            guard raw.count >= MemoryLayout<sockaddr_in>.size else { return nil }
            let sin = base.assumingMemoryBound(to: sockaddr_in.self)
            var addr = sin.pointee.sin_addr
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            let ip = String(cString: buf)
            let port = UInt16(bigEndian: sin.pointee.sin_port)
            return (ip, port, true)
        case AF_INET6:
            guard raw.count >= MemoryLayout<sockaddr_in6>.size else { return nil }
            let sin6 = base.assumingMemoryBound(to: sockaddr_in6.self)
            var addr6 = sin6.pointee.sin6_addr
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &addr6, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
            let ip = String(cString: buf)
            let port = UInt16(bigEndian: sin6.pointee.sin6_port)
            return (ip, port, false)
        default:
            return nil
        }
    }
}

/// Choose a preferred IPv4 (RFC1918) endpoint from NetService addresses; also returns printable IP list.
func choosePreferredEndpoint(from addresses: [Data]) -> (preferred: NWEndpoint?, ips: [String]) {
    var ips: [String] = []
    var firstIPv4: (String, UInt16)?
    var privateIPv4: (String, UInt16)?

    for d in addresses {
        if let pretty = renderSockaddr(d) { ips.append(pretty) }
        guard let (host, port, isV4) = parseSockaddrHostPort(d) else { continue }
        if isV4 {
            if firstIPv4 == nil { firstIPv4 = (host, port) }
            if privateIPv4 == nil, isPrivateIPv4(host) { privateIPv4 = (host, port) }
        }
    }

    let pick = privateIPv4 ?? firstIPv4
    if let (host, port) = pick, let nwPort = NWEndpoint.Port(rawValue: port) {
        if let ip = IPv4Address(host) {
            return (.hostPort(host: .ipv4(ip), port: nwPort), ips)
        } else {
            return (.hostPort(host: .name(host, nil), port: nwPort), ips)
        }
    }
    return (nil, ips)
}
