//
//  BeamMessages.swift
//  BeamCore
//
//  Created by . . on 9/22/25.
//

import Foundation
import Network

public enum BeamRole: String, Codable { case host, viewer }

public enum BeamError: Error, LocalizedError {
    case invalidMessage
    case handshakeRejected(String)
    case connectionFailed(String)
    case cancelled
    case alreadyRunning
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .invalidMessage:                   return "Invalid message"
        case .handshakeRejected(let reason):    return "Pairing rejected: \(reason)"
        case .connectionFailed(let reason):     return "Connection failed: \(reason)"
        case .cancelled:                        return "Cancelled"
        case .alreadyRunning:                   return "Already running"
        case .notRunning:                       return "Not running"
        }
    }
}

// MARK: - Control messages

public struct HandshakeRequest: Codable, Equatable {
    public let app: String = "beamroom"
    public let ver: Int = 1
    public let role: BeamRole
    public let code: String
    public init(role: BeamRole = .viewer, code: String) {
        self.role = role
        self.code = code
    }
}

public struct HandshakeResponse: Codable, Equatable {
    public let ok: Bool
    public let sessionID: UUID?
    public let udpPort: UInt16?
    public let message: String?
    public init(ok: Bool, sessionID: UUID? = nil, udpPort: UInt16? = nil, message: String? = nil) {
        self.ok = ok
        self.sessionID = sessionID
        self.udpPort = udpPort
        self.message = message
    }
}

/// Heartbeat frame (required `hb` key to avoid mis-decodes)
public struct Heartbeat: Codable, Equatable {
    public let hb: Int
    public init(hb: Int = 1) { self.hb = hb }
}

/// M2: Broadcast status
public struct BroadcastStatus: Codable, Equatable {
    public let on: Bool
    public init(on: Bool) { self.on = on }
}

/// M3: Media parameters (pushed when available/changed)
public struct MediaParams: Codable, Equatable {
    public let udpPort: UInt16
    public init(udpPort: UInt16) { self.udpPort = udpPort }
}

// MARK: - Newline-delimited JSON framing

enum Frame {
    static let nl = UInt8(0x0A)

    static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        var out = Data(capacity: data.count + 1)
        out.append(data)
        out.append(nl)
        return out
    }

    /// Append incoming → buffer, return complete newline-terminated frames
    @discardableResult
    static func drainLines(buffer: inout Data, incoming: Data) -> [Data] {
        buffer.append(incoming)
        var lines: [Data] = []
        while let idx = buffer.firstIndex(of: nl) {
            let line = buffer.prefix(upTo: idx)
            lines.append(Data(line))
            buffer.removeSubrange(...idx) // drop line + newline
        }
        return lines
    }
}

// MARK: - Discovered Host model

public struct DiscoveredHost: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    /// Original Bonjour service endpoint (works everywhere).
    public let endpoint: NWEndpoint
    /// Preferred infrastructure IPv4 endpoint (set when we resolve addresses).
    public var preferredEndpoint: NWEndpoint?
    /// For diagnostics/UI
    public var resolvedIPs: [String] = []

    public init(name: String, endpoint: NWEndpoint, preferredEndpoint: NWEndpoint? = nil, resolvedIPs: [String] = []) {
        self.name = name
        self.endpoint = endpoint
        self.preferredEndpoint = preferredEndpoint
        self.resolvedIPs = resolvedIPs
    }

    /// Use this when connecting: pick IPv4 infra if available, else the service.
    public var connectEndpoint: NWEndpoint { preferredEndpoint ?? endpoint }
}
