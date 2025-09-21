//
//  Transport.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//
//  M1 — Discovery & pairing (Wi-Fi Aware + control channel)
//  • Bonjour name extraction via NWEndpoint.service
//  • Per-connection line buffers stored in a dictionary (no captured inout)
//  • All state/receive callbacks hop to MainActor before touching @Published
//  • Explicit SendCompletion typing
//

import Foundation
import Network
import OSLog

public enum BeamRole: String, Codable { case host, viewer }

public struct BeamVersion {
    public static let string = "0.1.0-M1"
}

public enum BeamAppID {
    public static let string = "beamroom"
}

public enum BeamError: Error, LocalizedError {
    case invalidMessage
    case handshakeRejected(String)
    case connectionFailed(String)
    case cancelled
    case alreadyRunning
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .invalidMessage: return "Invalid message"
        case .handshakeRejected(let reason): return "Pairing rejected: \(reason)"
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        case .cancelled: return "Cancelled"
        case .alreadyRunning: return "Already running"
        case .notRunning: return "Not running"
        }
    }
}

// MARK: - Control messages

public struct HandshakeRequest: Codable, Equatable {
    public let app: String = BeamAppID.string
    public let ver: Int = 1
    public let role: BeamRole = .viewer
    public let code: String

    public init(code: String) { self.code = code }
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

public struct Heartbeat: Codable, Equatable { public let hb: Int = 1 }

// MARK: - Utilities

fileprivate enum Frame {
    static let newline = Data([0x0A]) // \n

    static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        var out = Data()
        out.append(data)
        out.append(newline)
        return out
    }

    @discardableResult
    static func drainLines(buffer: inout Data, incoming: Data) -> [Data] {
        buffer.append(incoming)
        var lines: [Data] = []
        while let range = buffer.firstRange(of: newline) {
            let line = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            lines.append(line)
        }
        return lines
    }
}

fileprivate extension Data {
    var utf8String: String { String(data: self, encoding: .utf8) ?? "" }
}

// MARK: - Discovery (Viewer)

public struct DiscoveredHost: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let endpoint: NWEndpoint

    public init(name: String, endpoint: NWEndpoint) {
        self.id = UUID()
        self.name = name
        self.endpoint = endpoint
    }

    public static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
        lhs.name == rhs.name && lhs.endpoint.debugDescription == rhs.endpoint.debugDescription
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(endpoint.debugDescription)
    }
}

@MainActor
public final class BeamBrowser: ObservableObject {
    @Published public private(set) var hosts: [DiscoveredHost] = []

    private var browser: NWBrowser?
    private let log = Logger(subsystem: BeamConfig.subsystemViewer, category: "browser")

    public init() {}

    public func start() throws {
        guard browser == nil else { throw BeamError.alreadyRunning }

        let descriptor = NWBrowser.Descriptor.bonjour(type: BeamConfig.controlService, domain: nil)
        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: descriptor, using: params)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.log.debug("Browser state: \(String(describing: state))")
            if case .failed(let err) = state {
                self.log.error("Browser failed: \(err.localizedDescription, privacy: .public)")
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var new: [DiscoveredHost] = []
            for result in results {
                var name = "Host"
                if case let .service(name: svcName, type: _, domain: _, interface: _) = result.endpoint {
                    name = svcName
                } else {
                    name = result.endpoint.debugDescription
                }
                new.append(DiscoveredHost(name: name, endpoint: result.endpoint))
            }
            new.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            Task { @MainActor in self.hosts = new }
        }

        browser.start(queue: .main)
        log.info("Discovery started for \(BeamConfig.controlService, privacy: .public)")
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        hosts.removeAll()
        log.info("Discovery stopped")
    }
}

// MARK: - Host Control Server

public struct PendingPair: Identifiable, Equatable {
    public let id: UUID
    public let code: String
    public let receivedAt: Date
    public let remoteDescription: String
    fileprivate let connection: NWConnection

    public init(code: String, remoteDescription: String, connection: NWConnection) {
        self.id = UUID()
        self.code = code
        self.receivedAt = Date()
        self.remoteDescription = remoteDescription
        self.connection = connection
    }
    public static func == (lhs: PendingPair, rhs: PendingPair) -> Bool { lhs.id == rhs.id }
}

public struct ActiveSession: Identifiable, Equatable {
    public let id: UUID
    public let startedAt: Date
    public let remoteDescription: String
}

@MainActor
public final class BeamControlServer: ObservableObject {
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var publishedName: String?
    @Published public private(set) var pendingPairs: [PendingPair] = []
    @Published public private(set) var sessions: [ActiveSession] = []

    private var listener: NWListener?
    private var pendingByID: [UUID: PendingPair] = [:]
    private var connections: [NWConnection] = []              // strong refs
    private var rxBuffers: [ObjectIdentifier: Data] = [:]     // per-connection line buffers

    private let log = Logger(subsystem: BeamConfig.subsystemHost, category: "control-server")

    public init() {}

    public func start(serviceName: String) throws {
        guard listener == nil else { throw BeamError.alreadyRunning }

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let listener = try NWListener(using: params)
        self.listener = listener
        listener.service = NWListener.Service(name: serviceName, type: BeamConfig.controlService)

        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            Task { @MainActor in self.handle(newConnection: conn) }
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self.isRunning = true
                    self.publishedName = serviceName
                }
                self.log.info("Control server ready as \(serviceName, privacy: .public) on \(BeamConfig.controlService, privacy: .public)")
            case .failed(let err):
                self.log.error("Listener failed: \(err.localizedDescription, privacy: .public)")
                Task { @MainActor in
                    self.isRunning = false
                    self.publishedName = nil
                }
            case .cancelled:
                self.log.info("Listener cancelled")
                Task { @MainActor in
                    self.isRunning = false
                    self.publishedName = nil
                }
            default: break
            }
        }

        listener.start(queue: .main)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for c in connections { c.cancel() }
        connections.removeAll()
        pendingPairs.removeAll()
        pendingByID.removeAll()
        rxBuffers.removeAll()
        isRunning = false
        publishedName = nil
    }

    @MainActor
    public func accept(_ id: UUID) {
        guard let pending = pendingByID[id] else { return }

        let sessionID = UUID()
        let response = HandshakeResponse(ok: true, sessionID: sessionID, udpPort: 0, message: nil)
        send(response, over: pending.connection)

        // Move to sessions
        let sess = ActiveSession(id: sessionID, startedAt: Date(), remoteDescription: pending.remoteDescription)
        sessions.append(sess)

        // Precompute a Sendable key so we don't capture 'pending' (non-Sendable) in @Sendable closure
        let key = ObjectIdentifier(pending.connection)

        pending.connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .cancelled, .failed:
                Task { @MainActor in
                    self.removeSession(id: sessionID)
                    // Clean per-connection buffers and strong-ref list without capturing the NWConnection itself
                    self.rxBuffers.removeValue(forKey: key)
                    self.connections.removeAll { ObjectIdentifier($0) == key }
                }
            default:
                break
            }
        }

        // No longer need the pending request entry
        removePending(id: id)
    }

    public func decline(_ id: UUID) {
        guard let pending = pendingByID[id] else { return }
        let response = HandshakeResponse(ok: false, sessionID: nil, udpPort: nil, message: "Declined")
        send(response, over: pending.connection)
        pending.connection.cancel()
        removePending(id: id)
    }

    private func removePending(id: UUID) {
        pendingByID.removeValue(forKey: id)
        pendingPairs.removeAll { $0.id == id }
    }

    private func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
    }

    private func handle(newConnection conn: NWConnection) {
        connections.append(conn)
        rxBuffers[ObjectIdentifier(conn)] = Data()

        let whereFrom = conn.endpoint.debugDescription
        log.debug("Incoming connection from \(whereFrom, privacy: .public)")

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log.debug("Conn ready (\(whereFrom, privacy: .public)) — awaiting handshake")
                Task { @MainActor in self.receiveNext(on: conn) }
            case .failed(let err):
                self.log.error("Conn failed (\(whereFrom, privacy: .public)): \(err.localizedDescription, privacy: .public)")
                Task { @MainActor in
                    self.connections.removeAll { $0 === conn }
                    self.rxBuffers.removeValue(forKey: ObjectIdentifier(conn))
                }
            case .cancelled:
                self.log.debug("Conn cancelled (\(whereFrom, privacy: .public))")
                Task { @MainActor in
                    self.connections.removeAll { $0 === conn }
                    self.rxBuffers.removeValue(forKey: ObjectIdentifier(conn))
                }
            default: break
            }
        }

        conn.start(queue: .main)
    }

    // NOTE: No 'inout' buffer — we manage per-conn buffers in rxBuffers.
    private func receiveNext(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                Task { @MainActor in
                    self.log.error("Receive error: \(error.localizedDescription, privacy: .public)")
                    conn.cancel()
                    self.rxBuffers.removeValue(forKey: ObjectIdentifier(conn))
                }
                return
            }

            if let data, !data.isEmpty {
                Task { @MainActor in
                    let key = ObjectIdentifier(conn)
                    var buffer = self.rxBuffers[key] ?? Data()
                    let lines = Frame.drainLines(buffer: &buffer, incoming: data)
                    self.rxBuffers[key] = buffer
                    for line in lines {
                        self.handleLine(line, from: conn)
                    }
                }
            }

            if isComplete {
                Task { @MainActor in
                    self.log.debug("Conn completed by remote")
                    conn.cancel()
                    self.rxBuffers.removeValue(forKey: ObjectIdentifier(conn))
                }
                return
            }

            // Continue loop
            Task { @MainActor in self.receiveNext(on: conn) }
        }
    }

    private func handleLine(_ line: Data, from conn: NWConnection) {
        do {
            let req = try JSONDecoder().decode(HandshakeRequest.self, from: line)
            guard req.app == BeamAppID.string, req.ver == 1, req.role == .viewer else {
                throw BeamError.invalidMessage
            }
            let pending = PendingPair(code: req.code,
                                      remoteDescription: conn.endpoint.debugDescription,
                                      connection: conn)
            pendingByID[pending.id] = pending
            pendingPairs.append(pending)
            log.info("Pair request: code \(req.code, privacy: .public) from \(pending.remoteDescription, privacy: .public)")
        } catch {
            log.error("Invalid handshake: \(line.utf8String, privacy: .public)")
            let response = HandshakeResponse(ok: false, sessionID: nil, udpPort: nil, message: "Invalid handshake")
            send(response, over: conn)
            conn.cancel()
            rxBuffers.removeValue(forKey: ObjectIdentifier(conn))
        }
    }

    private func send<T: Encodable>(_ payload: T, over conn: NWConnection) {
        do {
            let framed = try Frame.encodeLine(payload)
            conn.send(content: framed,
                      completion: NWConnection.SendCompletion.contentProcessed({ [weak self] (sendErr: NWError?) in
                if let sendErr {
                    self?.log.error("Send error: \(sendErr.localizedDescription, privacy: .public)")
                }
            }))
        } catch {
            log.error("Encoding error: \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - Viewer Control Client

public enum ClientStatus: Equatable {
    case idle
    case connecting(hostName: String, code: String)
    case waitingAcceptance(code: String)
    case paired(sessionID: UUID, udpPort: UInt16)
    case failed(String)
}

@MainActor
public final class BeamControlClient: ObservableObject {
    @Published public private(set) var status: ClientStatus = .idle

    private var connection: NWConnection?
    private var hbTask: Task<Void, Never>?
    private var rxBuffer = Data()
    private let log = Logger(subsystem: BeamConfig.subsystemViewer, category: "control-client")

    public init() {}

    public func connect(to host: DiscoveredHost, code: String) {
        disconnect()

        status = .connecting(hostName: host.name, code: code)
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let conn = NWConnection(to: host.endpoint, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self.log.debug("Client ready → sending handshake")
                    self.sendHandshake(code: code)
                    self.status = .waitingAcceptance(code: code)
                    self.receiveNext()
                    self.startHeartbeats()
                }
            case .failed(let err):
                Task { @MainActor in
                    self.log.error("Client failed: \(err.localizedDescription, privacy: .public)")
                    self.status = .failed(err.localizedDescription)
                    self.disconnect()
                }
            case .cancelled:
                Task { @MainActor in
                    self.log.debug("Client cancelled")
                    self.status = .idle
                }
            default: break
            }
        }

        conn.start(queue: .main)
    }

    public func disconnect() {
        hbTask?.cancel()
        hbTask = nil
        connection?.cancel()
        connection = nil
        rxBuffer.removeAll()
    }

    public static func randomCode() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }

    private func sendHandshake(code: String) {
        guard let conn = connection else { return }
        let req = HandshakeRequest(code: code)
        do {
            let data = try Frame.encodeLine(req)
            conn.send(content: data,
                      completion: NWConnection.SendCompletion.contentProcessed({ [weak self] (_: NWError?) in
                _ = self
            }))
        } catch {
            log.error("Encode handshake failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func receiveNext() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.log.error("Receive error: \(error.localizedDescription, privacy: .public)")
                    self.status = .failed(error.localizedDescription)
                    self.disconnect()
                }
                return
            }
            if let data, !data.isEmpty {
                let lines = Frame.drainLines(buffer: &self.rxBuffer, incoming: data)
                for line in lines {
                    Task { @MainActor in self.handleLine(line) }
                }
            }
            if isComplete {
                Task { @MainActor in
                    self.log.debug("Server closed connection")
                    self.disconnect()
                }
                return
            }
            self.receiveNext()
        }
    }

    private func handleLine(_ line: Data) {
        if case .waitingAcceptance = status {
            do {
                let resp = try JSONDecoder().decode(HandshakeResponse.self, from: line)
                if resp.ok, let sid = resp.sessionID {
                    let port = resp.udpPort ?? 0
                    status = .paired(sessionID: sid, udpPort: port)
                    log.info("Paired ✓ — session \(sid.uuidString, privacy: .public), udp \(port)")
                } else {
                    status = .failed(resp.message ?? "Rejected")
                    disconnect()
                }
            } catch {
                log.error("Bad response: \(line.utf8String, privacy: .public)")
                status = .failed("Bad response")
                disconnect()
            }
        } else {
            log.debug("Received line: \(line.utf8String, privacy: .public)")
        }
    }

    private func startHeartbeats() {
        hbTask?.cancel()
        hbTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    let shouldHB: Bool
                    switch self.status {
                    case .waitingAcceptance, .paired: shouldHB = true
                    default: shouldHB = false
                    }
                    guard shouldHB else { return }
                    let hb = Heartbeat()
                    do {
                        let data = try Frame.encodeLine(hb)
                        self.connection?.send(content: data,
                                              completion: NWConnection.SendCompletion.contentProcessed({ (_: NWError?) in }))
                    } catch {
                        // ignore
                    }
                }
            }
        }
    }
}
