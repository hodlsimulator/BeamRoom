//
//  Transport.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//
//  Discovery & pairing
//  • NWBrowser + NetServiceBrowser in parallel (Bonjour, P2P)
//  • NWListener + NetService publish (fixed TCP control port)
//  • JSONL handshake
//

import Foundation
import Network
import OSLog

// MARK: - Roles, errors

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

public struct Heartbeat: Codable, Equatable { public let hb: Int = 1 }

// MARK: - Framing helpers (JSONL)

fileprivate enum Frame {
    static let nl = UInt8(0x0A)

    static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        var out = Data(capacity: data.count + 1)
        out.append(data)
        out.append(nl)
        return out
    }

    @discardableResult
    static func drainLines(buffer: inout Data, incoming: Data) -> [Data] {
        buffer.append(incoming)
        var lines: [Data] = []
        while let idx = buffer.firstIndex(of: nl) {
            let end = buffer.index(after: idx)
            let line = buffer.prefix(upTo: idx)
            lines.append(Data(line))
            buffer.removeSubrange(..<end)
        }
        return lines
    }
}

// MARK: - Discovery model

public struct DiscoveredHost: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint

    public init(name: String, endpoint: NWEndpoint) {
        self.name = name
        self.endpoint = endpoint
        self.id = "\(name)|\(endpoint.debugDescription)"
    }
}

// MARK: - Viewer: Browser (NWBrowser + NetServiceBrowser)

private let browserLog = Logger(subsystem: BeamConfig.subsystemViewer, category: "browser")

public final class BeamBrowser: NSObject, ObservableObject {
    @Published public private(set) var hosts: [DiscoveredHost] = []

    private var nwBrowser: NWBrowser?
    private var nsBrowser: NetServiceBrowser?
    private var nsServices: [NetService] = []

    // Keep an aggregate keyed by endpoint description.
    private var aggregate: [String: DiscoveredHost] = [:]

    public override init() { super.init() }

    public func start() throws {
        guard nwBrowser == nil, nsBrowser == nil else { throw BeamError.alreadyRunning }

        Task { @MainActor in
            self.aggregate.removeAll()
            self.hosts.removeAll()
        }

        // A) NWBrowser (Bonjour)
        let descriptor = NWBrowser.Descriptor.bonjour(type: BeamConfig.controlService, domain: nil)
        let params = NWParameters()
        params.includePeerToPeer = true
        let nw = NWBrowser(for: descriptor, using: params)
        self.nwBrowser = nw

        nw.stateUpdateHandler = { state in
            browserLog.debug("NWBrowser state: \(String(describing: state))")
            if case .failed(let err) = state {
                browserLog.error("NWBrowser failed: \(err.localizedDescription, privacy: .public)")
            }
        }

        nw.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            Task { @MainActor in
                var newAgg: [String: DiscoveredHost] = [:]
                for r in results {
                    let ep = r.endpoint
                    let name: String
                    if case let .service(name: svcName, type: _, domain: _, interface: _) = ep {
                        name = svcName
                    } else {
                        name = "Host"
                    }
                    newAgg[ep.debugDescription] = DiscoveredHost(name: name, endpoint: ep)
                }
                self.aggregate = newAgg
                self.publishHosts()
            }
        }

        nw.start(queue: .main)
        browserLog.info("NWBrowser started for \(BeamConfig.controlService, privacy: .public)")

        // B) NetServiceBrowser (Bonjour classic)
        let nsb = NetServiceBrowser()
        nsb.includesPeerToPeer = true
        nsb.delegate = self
        self.nsBrowser = nsb

        let typeToSearch = BeamConfig.controlService.hasSuffix(".") ? BeamConfig.controlService : BeamConfig.controlService + "."
        nsb.searchForServices(ofType: typeToSearch, inDomain: "local.")
        browserLog.info("NetServiceBrowser started for \(typeToSearch, privacy: .public)")
    }

    public func stop() {
        nwBrowser?.cancel(); nwBrowser = nil
        nsBrowser?.stop(); nsBrowser = nil
        for s in nsServices { s.stop() }
        nsServices.removeAll()
        Task { @MainActor in
            self.aggregate.removeAll()
            self.hosts.removeAll()
        }
        browserLog.info("Discovery stopped")
    }

    @MainActor private func publishHosts() {
        var list = Array(aggregate.values)
        list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.hosts = list
    }
}

extension BeamBrowser: NetServiceBrowserDelegate, NetServiceDelegate {
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.includesPeerToPeer = true
        nsServices.append(service)

        let name = service.name
        let type = service.type.hasSuffix(".") ? String(service.type.dropLast()) : service.type
        let domain = service.domain.isEmpty ? "local." : service.domain
        let ep = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)

        Task { @MainActor in
            self.aggregate[ep.debugDescription] = DiscoveredHost(name: name, endpoint: ep)
            if !moreComing { self.publishHosts() }
        }
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let name = service.name
        let type = service.type.hasSuffix(".") ? String(service.type.dropLast()) : service.type
        let domain = service.domain.isEmpty ? "local." : service.domain
        let ep = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)

        Task { @MainActor in
            self.aggregate.removeValue(forKey: ep.debugDescription)
            if !moreComing { self.publishHosts() }
        }
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        browserLog.error("NetServiceBrowser error: \(String(describing: errorDict), privacy: .public)")
    }
}

// MARK: - Host control server (NWListener + NetService) with fixed port

private let serverLog = Logger(subsystem: BeamConfig.subsystemHost, category: "control-server")
private let bonjourLog = Logger(subsystem: BeamConfig.subsystemHost, category: "bonjour")

public struct PendingPair: Identifiable, Equatable {
    public let id = UUID()
    public let code: String
    public let receivedAt: Date
    public let remoteDescription: String
    fileprivate let connection: NWConnection

    public static func == (lhs: PendingPair, rhs: PendingPair) -> Bool { lhs.id == rhs.id }

    public init(code: String, remoteDescription: String, connection: NWConnection) {
        self.code = code
        self.receivedAt = Date()
        self.remoteDescription = remoteDescription
        self.connection = connection
    }
}

public struct ActiveSession: Identifiable, Equatable {
    public let id: UUID
    public let startedAt: Date
    public let remoteDescription: String
}

public final class BeamControlServer: NSObject, ObservableObject {
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var publishedName: String?
    @Published public private(set) var pendingPairs: [PendingPair] = []
    @Published public private(set) var sessions: [ActiveSession] = []

    private var listener: NWListener?
    private var netService: NetService?
    private var pendingByID: [UUID: PendingPair] = [:]
    private var connections: [NWConnection] = []
    private var rxBuffers: [ObjectIdentifier: Data] = [:]

    public override init() { super.init() }

    @MainActor
    public func start(serviceName: String) throws {
        guard listener == nil else { throw BeamError.alreadyRunning }

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        guard let port = NWEndpoint.Port(rawValue: BeamConfig.controlPort) else {
            throw BeamError.connectionFailed("Bad control port")
        }
        let l = try NWListener(using: params, on: port)
        self.listener = l

        l.stateUpdateHandler = { state in
            serverLog.debug("Listener state: \(String(describing: state))")
            if case .failed(let err) = state {
                serverLog.error("Listener failed: \(err.localizedDescription, privacy: .public)")
            }
        }

        l.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            Task { @MainActor in
                self.handleIncoming(conn)
            }
        }

        l.start(queue: .main)

        // Bonjour advertise on the same fixed port
        let type = BeamConfig.controlService.hasSuffix(".") ? BeamConfig.controlService : BeamConfig.controlService + "."
        let ns = NetService(domain: "local.", type: type, name: serviceName, port: Int32(BeamConfig.controlPort))
        ns.includesPeerToPeer = true
        ns.delegate = self
        ns.publish()
        self.netService = ns
        self.publishedName = serviceName

        self.isRunning = true
        serverLog.info("Control server started on \(BeamConfig.controlPort), bonjour '\(serviceName)'")
    }

    @MainActor
    public func stop() {
        netService?.stop(); netService = nil
        listener?.cancel(); listener = nil

        for c in connections { c.cancel() }
        connections.removeAll()
        rxBuffers.removeAll()
        pendingPairs.removeAll()
        pendingByID.removeAll()
        sessions.removeAll()

        publishedName = nil
        isRunning = false
        serverLog.info("Control server stopped")
    }

    @MainActor
    public func accept(_ id: UUID) {
        guard let p = pendingByID.removeValue(forKey: id) else { return }
        pendingPairs.removeAll { $0.id == id }
        let sid = UUID()
        let resp = HandshakeResponse(ok: true, sessionID: sid, udpPort: nil, message: "OK")
        sendResponse(resp, over: p.connection)
        sessions.append(ActiveSession(id: sid, startedAt: Date(), remoteDescription: p.remoteDescription))
    }

    @MainActor
    public func decline(_ id: UUID) {
        guard let p = pendingByID.removeValue(forKey: id) else { return }
        pendingPairs.removeAll { $0.id == id }
        let resp = HandshakeResponse(ok: false, sessionID: nil, udpPort: nil, message: "Declined")
        sendResponse(resp, over: p.connection)
        p.connection.cancel()
    }

    @MainActor
    private func handleIncoming(_ conn: NWConnection) {
        connections.append(conn)
        let key = ObjectIdentifier(conn)
        rxBuffers[key] = Data()

        conn.stateUpdateHandler = { state in
            serverLog.debug("Incoming conn state: \(String(describing: state))")
            if case .failed(let err) = state {
                serverLog.error("Incoming failed: \(err.localizedDescription, privacy: .public)")
            }
        }

        conn.start(queue: .main)
        receiveLoop(conn)
    }

    private func receiveLoop(_ conn: NWConnection) {
        let key = ObjectIdentifier(conn)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isEOF, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                Task { @MainActor in
                    var buf = self.rxBuffers[key] ?? Data()
                    for line in Frame.drainLines(buffer: &buf, incoming: data) {
                        self.handleLine(line, from: conn)
                    }
                    self.rxBuffers[key] = buf
                }
            }
            if isEOF || error != nil {
                Task { @MainActor in
                    self.rxBuffers.removeValue(forKey: key)
                    conn.cancel()
                    self.connections.removeAll { $0 === conn }
                }
                return
            }
            self.receiveLoop(conn)
        }
    }

    @MainActor
    private func handleLine(_ line: Data, from conn: NWConnection) {
        if let req = try? JSONDecoder().decode(HandshakeRequest.self, from: line) {
            let remote = conn.currentPath?.remoteEndpoint?.debugDescription ?? "peer"
            let p = PendingPair(code: req.code, remoteDescription: remote, connection: conn)
            pendingByID[p.id] = p
            pendingPairs.append(p)
            serverLog.info("Pending pair from \(remote, privacy: .public) code \(req.code, privacy: .public)")
            return
        }
        serverLog.error("Invalid line on control connection")
    }

    @MainActor
    private func sendResponse(_ resp: HandshakeResponse, over conn: NWConnection) {
        do {
            let bytes = try Frame.encodeLine(resp)
            conn.send(content: bytes, completion: .contentProcessed { _ in })
            if !resp.ok { conn.cancel() }
        } catch {
            serverLog.error("Failed to encode response: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension BeamControlServer: NetServiceDelegate {
    public func netServiceDidPublish(_ sender: NetService) {
        bonjourLog.info("Published \(sender.name, privacy: .public)")
    }
    public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        bonjourLog.error("Publish error: \(String(describing: errorDict), privacy: .public)")
    }
}

// MARK: - Viewer control client

private let clientLog = Logger(subsystem: BeamConfig.subsystemViewer, category: "control-client")

public final class BeamControlClient: ObservableObject {
    public enum Status: Equatable {
        case idle
        case connecting(hostName: String, remote: String)
        case waitingAcceptance
        case paired(session: UUID, udpPort: UInt16?)
        case failed(reason: String)
    }

    @Published public private(set) var status: Status = .idle

    private var connection: NWConnection?
    private var rxBuffer = Data()

    public init() {}

    public static func randomCode() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }

    public func connect(to host: DiscoveredHost, code: String) {
        disconnect()

        // Capture only sendable values to keep the state handler clean.
        let hostName = host.name
        let remoteDesc = host.endpoint.debugDescription

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let conn = NWConnection(to: host.endpoint, using: params)
        self.connection = conn

        Task { @MainActor in
            self.status = .connecting(hostName: hostName, remote: remoteDesc)
        }

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                clientLog.info("Control ready to \(hostName, privacy: .public)")
                Task { @MainActor in
                    self.sendHandshake(code: code)
                    self.receiveLoop()
                }
            case .failed(let err):
                Task { @MainActor in
                    self.status = .failed(reason: err.localizedDescription)
                    self.connection?.cancel()
                    self.connection = nil
                }
            case .cancelled:
                Task { @MainActor in
                    if case .failed = self.status { /* keep failed */ } else {
                        self.status = .idle
                    }
                }
            default:
                break
            }
        }

        conn.start(queue: .main)
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        rxBuffer.removeAll()
        Task { @MainActor in
            self.status = .idle
        }
    }

    @MainActor
    private func sendHandshake(code: String) {
        guard let conn = connection else { return }
        let req = HandshakeRequest(role: .viewer, code: code)
        do {
            let bytes = try Frame.encodeLine(req)
            status = .waitingAcceptance
            conn.send(content: bytes, completion: .contentProcessed { _ in })
        } catch {
            status = .failed(reason: "Encode failed")
            conn.cancel()
        }
    }

    private func receiveLoop() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isEOF, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                for line in Frame.drainLines(buffer: &self.rxBuffer, incoming: data) {
                    self.handleLine(line)
                }
            }
            if isEOF || error != nil {
                Task { @MainActor in
                    if case .paired = self.status {
                        // Keep paired if peer closed intentionally.
                    } else if case .failed = self.status {
                        // keep failed
                    } else {
                        self.status = .failed(reason: "Disconnected")
                    }
                    self.connection?.cancel()
                    self.connection = nil
                }
                return
            }
            self.receiveLoop()
        }
    }

    private func handleLine(_ line: Data) {
        if let resp = try? JSONDecoder().decode(HandshakeResponse.self, from: line) {
            Task { @MainActor in
                if resp.ok, let sid = resp.sessionID {
                    self.status = .paired(session: sid, udpPort: resp.udpPort)
                } else {
                    self.status = .failed(reason: resp.message ?? "Rejected")
                }
            }
            return
        }
        clientLog.error("Invalid response frame")
    }
}

// MARK: - Sendable shims for @Sendable handlers

extension BeamBrowser: @unchecked Sendable {}
extension BeamControlServer: @unchecked Sendable {}
extension BeamControlClient: @unchecked Sendable {}
