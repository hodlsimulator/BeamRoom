//
//  BeamMessages.swift
//  BeamCore
//
//  Created by . . on 9/22/25.
//
//  Control-plane messages + tiny JSON-Lines framing helper.
//

import Foundation
import Network

// MARK: - Errors

public enum BeamError: Error, LocalizedError {
    case invalidMessage
    case handshakeRejected(String)
    case connectionFailed(String)
    case cancelled
    case alreadyRunning
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .invalidMessage:               return "Invalid message"
        case .handshakeRejected(let r):     return "Pairing rejected: \(r)"
        case .connectionFailed(let r):      return "Connection failed: \(r)"
        case .cancelled:                    return "Cancelled"
        case .alreadyRunning:               return "Already running"
        case .notRunning:                   return "Not running"
        }
    }
}

public enum BeamRole: String, Codable { case host, viewer }

// MARK: - Control messages

/// M1: Viewer → Host
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

/// M1 reply: Host → Viewer
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

/// Heartbeat frame (explicit key to avoid accidental mis-decodes)
public struct Heartbeat: Codable, Equatable {
    public let hb: Int
    public init(hb: Int = 1) { self.hb = hb }
}

/// M3: Media parameters (Host → Viewer)
public struct MediaParams: Codable, Equatable {
    public let udpPort: UInt16
    public init(udpPort: UInt16) { self.udpPort = udpPort }
}

// NOTE: BroadcastStatus lives in its own file (BroadcastStatus.swift) to avoid redeclaration.
// public struct BroadcastStatus: Codable, Equatable { ... }

// MARK: - Newline-delimited JSON framing

enum Frame {
    static let nl = UInt8(0x0A)

    /// Encode as a single JSON line terminated by '\n'
    static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        let enc = JSONEncoder()
        let data = try enc.encode(value)
        var out = Data(capacity: data.count + 1)
        out.append(data)
        out.append(nl)
        return out
    }

    /// Append incoming data and drain any complete lines (without the trailing '\n')
    @discardableResult
    static func drainLines(buffer: inout Data, incoming: Data) -> [Data] {
        buffer.append(incoming)
        var lines: [Data] = []
        while let idx = buffer.firstIndex(of: nl) {
            let line = buffer.prefix(upTo: idx)       // excludes '\n'
            lines.append(Data(line))
            buffer.removeSubrange(...idx)             // also drop '\n'
        }
        return lines
    }
}

// MARK: - Discovery model (Viewer UI)

/// What the Viewer shows in its Host list.
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
    public var connectEndpoint: NWEndpoint {
        preferredEndpoint ?? endpoint
    }
}
