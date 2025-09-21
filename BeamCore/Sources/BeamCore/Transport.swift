//
//  Transport.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//
//  Discovery & pairing
//  • NWBrowser + NetServiceBrowser in parallel (Bonjour)
//  • NWListener + NetService publish (Bonjour)
//  • Optional Wi-Fi Aware UI paths (guarded elsewhere)
//  • Manual IP connect fallback using a fixed control port
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
        self.ok = ok; self.sessionID = sessionID; self.udpPort = udpPort; self.message = message
    }
}

public struct Heartbeat: Codable, Equatable { public let hb: Int = 1 }

// MARK: - Helpers

fileprivate enum Frame {
    static let nl = UInt8(0x0A)

    static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        var out = Data(capacity: data.count + 1)
        out.append(data); out.append(nl)
        return out
    }

    @discardableResult
    static func drainLines(buffer: inout Data, incoming: Data) -> [Data] {
        buffer.append(incoming)
        var lines: [Data] = []
        while let idx = buffer.firstIndex(of: nl) {
            let line = buffer.prefix(upTo: idx)
            lines.append(Data(line))
            buffer.removeSubrange(..<buffer.index(after: idx))
        }
        return lines
    }
}

fileprivate extension Data {
    var utf8String: String { String(data: self, encoding: .utf8) ?? "<non-UTF8 \(count) bytes>" }
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

public final class BeamBrowser: NSObject, ObservableObject {

    @Published public private(set) var hosts: [DiscoveredHost] = []

    private var nwBrowser: NWBrowser?
    private var nsBrowser: NetServiceBrowser?
    private var aggregate: [String: DiscoveredHost] = [:] // mutated on MainActor
    private let log = Logger(subsystem: BeamConfig.subsystemViewer, category: "browser")

    private var nsServices: [NetService] = []

    public override init() { }

    public func start() throws {
        guard nwBrowser == nil, nsBrowser == nil else { throw BeamError.alreadyRunning }

        Task { @MainActor in
            self.aggregate.removeAll()
            self.hosts.removeAll()
        }

        // Path A: NWBrowser (Bonjour)
        let descriptor = NWBrowser.Descriptor.bonjour(type: BeamConfig.controlService, domain: nil)
        let params = NWParameters()
        params.includePeerToPeer = true
        let nw = NWBrowser(for: descriptor, using: params)
        self.nwBrowser = nw

        nw.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.log.debug("NWBrowser state: \(String(describing: state))")
            if case .failed(let err) = state {
                self.log.error("NWBrowser failed: \(err.localizedDescription, privacy: .public)")
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
                    } else { name = "Host" }
                    newAgg[ep.debugDescription] = DiscoveredHost(name: name, endpoint: ep)
                }
                self.aggregate = newAgg
                self.publishHosts()
            }
        }

        nw.start(queue: .main)
        log.info("NWBrowser started for \(BeamConfig.controlService, privacy: .public)")

        // Path B: NetServiceBrowser (Bonjour classic)
        let nsb = NetServiceBrowser()
        #if os(iOS)
        nsb.includesPeerToPeer = true
        #endif
        nsb.delegate = self
        self.nsBrowser = nsb

        let typeToSearch = BeamConfig.controlService.hasSuffix(".")
            ? BeamConfig.controlService
            : BeamConfig.controlService + "."
        nsb.searchForServices(ofType: typeToSearch, inDomain: "local.")
        log.info("NetServiceBrowser started for \(typeToSearch, privacy: .public)")
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
        log.info("Discovery stopped")
    }

    @MainActor private func publishHosts() {
        var list = Array(aggregate.values)
        list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.hosts = list
    }
}

extension BeamBrowser: @unchecked Sendable {}

extension BeamBrowser: NetServiceBrowserDelegate, NetServiceDelegate {

    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        #if os(iOS)
        service.includesPeerToPeer = true
        #endif
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
        log.error("NetServiceBrowser error: \(String(describing: errorDict), privacy: .public)")
    }
}

// MARK: - Host control server (NWListener + NetService) with fixed port

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

@MainActor
public final class BeamControlServer: ObservableObject {

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var publishedName: String?
    @Published public private(set) var pendingPairs: [PendingPair] = []
    @Published public private(set) var sessions: [ActiveSession] = []

    private var listener: NWListener?
    private var netService: NetService?
    private var pendingByID: [UUID: PendingPair] = [:]
    private var connections: [NWConnection] = []
    private var rxBuffers: [ObjectIdentifier: Data] = [:]

    private let log = Logger(subsystem: BeamConfig.subsystemHost, category: "control-server")

    public init() {}

    public func start(serviceName: String) throws {
        guard listener == nil else { throw BeamError.alreadyRunning }

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        guard let port = NWEndpoint.Port(rawValue: BeamConfig.controlPort) else {
            throw BeamError.connectionFailed("Bad control port")
        }
        let l = try NWListener(using: params, on: port)   // ← fixed port
                // If the port is in use, this throws; that’s fine during dev.
        listener = l
        l.service = NWListener.Service(name: serviceName, type: BeamConfig.controlService)

        l.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            Task { @MainActor in self.handle(newConnection: conn) }
        }

        l.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self.isRunning = true
                    self.publishedName = serviceName
                    self.publishNetServiceIfNeeded(serviceName: serviceName, listener: l)
                }
                self.log.info("Control server ready as \(serviceName, privacy: .public) on \(BeamConfig.controlService, privacy: .public) port \(BeamConfig.controlPort)")
            case .failed(let err):
                self.log.error("Listener failed: \(err.localizedDescription, privacy: .public)")
                Task { @MainActor in
                    self.isRunning = false; self.publishedName = nil
                    self.netService?.stop(); self.netService = nil
                }
            case .cancelled:
                self.log.info("Listener cancelled")
                Task { @MainActor in
                    self.isRunning = false; self.publishedName = nil
                    self.netService?.stop(); self.netService = nil
                }
            default: break
            }
        }

        l.start(queue: .main)
    }

    public func stop() {
        listener?.cancel(); listener = nil
        netService?.stop(); netService = nil
        for c in connections { c.cancel() }
        connections.removeAll()
        pendingPairs.removeAll()
        pendingByID.removeAll()
        rxBuffers.removeAll()
        isRunning = false
        publishedName = nil
    }

    private func publishNetServiceIfNeeded(serviceName: String, listener: NWListener) {
        guard netService == nil else { return }
        let port = Int32(BeamConfig.controlPort)
        let type = BeamConfig.controlService.hasSuffix(".")
            ? BeamConfig.controlService : BeamConfig.controlService + "."
        let s = NetService(domain: "local.", type: type, name: serviceName, port: port)
        #if os(iOS)
        s.includesPeerToPeer = true
        #endif
        s.publish()
        netService = s
        log.info("NetService published: \(serviceName, privacy: .public) \(type, privacy: .public) port \(port)")
    }

    public func accept(_ id: UUID) {
        guard let pending = pendingByID[id] else { return }
        let sessionID = UUID()
        let response = HandshakeResponse(ok: true, sessionID: sessionID, udpPort: 0, message: nil)
        send(response, over: pending.connection)

        let sess = ActiveSession(id: sessionID, startedAt: Date(), remoteDescription: pending.remoteDescription)
        sessions.append(sess)

        let key = ObjectIdentifier(pending.connection)
        pending.connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .cancelled, .failed:
                Task { @MainActor in
                    self.removeSession(id: sessionID)
                    self.rxBuffers.removeValue(forKey: key)
                    self.connections.removeAll { ObjectIdentifier($0) == key }
                }
            default: break
            }
        }

        removePending(id: id)
    }

    public func decline(_ id: UUID) {
        guard let pending = pendingByID[id] else { return }
        let response = HandshakeResponse(ok: false, sessionID: nil, udpPort: nil, message: "Declined")
        send(response, over: pending.connection)
        pending.connection.cancel()
        removePending(id: id)
    }

    private func removePending(id: UUID) { pendingByID.removeValue(forKey: id); pendingPairs.removeAll { $0.id == id } }
    private func removeSession(id: UUID) { sessions.removeAll { $0.id == id } }

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
                    for line in lines { self.handleLine(line, from: conn) }
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
            Task { @MainActor in self.receiveNext(on: conn) }
        }
    }

    private func handleLine(_ line: Data, from conn: NWConnection) {
        do {
            let req = try JSONDecoder().decode(HandshakeRequest.self, from: line)
            guard req.app == "beamroom", req.ver == 1, req.role == .viewer else {
                throw BeamError.invalidMessage
            }
            let pending = PendingPair(code: req.code, remoteDescription: conn.endpoint.debugDescription, connection: conn)
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
            conn.send(content: framed, completion: .contentProcessed { [weak self] sendErr in
                if let sendErr { self?.log.error("Send error: \(sendErr.localizedDescription, privacy: .public)") }
            })
        } catch {
            log.error("Encoding error: \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - Viewer: Control client (adds manual IP connect)

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

    // Existing: connect via Bonjour endpoint
    public func connect(to host: DiscoveredHost, code: String) {
        disconnect()
        status = .connecting(hostName: host.name, code: code)

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let conn = NWConnection(to: host.endpoint, using: params)
        self.connection = conn

        wireStateHandlers(sendCode: code)
        conn.start(queue: .main)
    }

    // NEW: manual IP connect (same Wi-Fi fallback)
    public func connect(ip: String, port: UInt16, code: String) {
        disconnect()
        status = .connecting(hostName: ip, code: code)

        let params = NWParameters.tcp
        params.includePeerToPeer = true   // harmless on Wi-Fi; allows AWDL if present

        guard let p = NWEndpoint.Port(rawValue: port) else {
            status = .failed("Bad port"); return
        }
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: p, using: params)
        self.connection = conn

        wireStateHandlers(sendCode: code)
        conn.start(queue: .main)
    }

    private func wireStateHandlers(sendCode: String) {
        connection?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self.log.debug("Client ready → sending handshake")
                    self.sendHandshake(code: sendCode)
                    self.status = .waitingAcceptance(code: sendCode)
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
                    self.log.debug("Client cancelled"); self.status = .idle
                }
            default: break
            }
        }
    }

    public func disconnect() {
        hbTask?.cancel(); hbTask = nil
        connection?.cancel(); connection = nil
        rxBuffer.removeAll()
    }

    public static func randomCode() -> String { String(format: "%04d", Int.random(in: 0...9999)) }

    private func sendHandshake(code: String) {
        guard let conn = connection else { return }
        let req = HandshakeRequest(code: code)
        do {
            let data = try Frame.encodeLine(req)
            conn.send(content: data, completion: .contentProcessed { _ in })
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
                for line in lines { Task { @MainActor in self.handleLine(line) } }
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
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self.sendHeartbeatIfNeeded()
            }
        }
    }

    @MainActor
    private func sendHeartbeatIfNeeded() {
        switch status {
        case .waitingAcceptance, .paired:
            do {
                let data = try Frame.encodeLine(Heartbeat())
                connection?.send(content: data, completion: .contentProcessed { _ in })
            } catch {
                // ignore
            }
        default:
            break
        }
    }
}
