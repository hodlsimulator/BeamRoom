//
//  Transport.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//
//  Discovery & pairing with in-app logging (conn IDs, path info, address resolution)
//

import Foundation
import Network
import OSLog
import Darwin

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
        case .invalidMessage:                 return "Invalid message"
        case .handshakeRejected(let reason):  return "Pairing rejected: \(reason)"
        case .connectionFailed(let reason):   return "Connection failed: \(reason)"
        case .cancelled:                      return "Cancelled"
        case .alreadyRunning:                 return "Already running"
        case .notRunning:                     return "Not running"
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

    /// Append incoming → buffer, return any complete newline-terminated frames
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

// MARK: - Shared helpers

fileprivate func short(_ t: NWInterface.InterfaceType) -> String {
    switch t {
    case .wifi: return "wifi"
    case .cellular: return "cell"
    case .wiredEthernet: return "wired"
    case .loopback: return "loop"
    case .other: return "other"
    @unknown default: return "?"
    }
}

fileprivate func pathSummary(_ p: NWPath?) -> String {
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

fileprivate func renderSockaddr(_ data: Data) -> String? {
    return data.withUnsafeBytes { raw -> String? in
        guard let base = raw.baseAddress else { return nil }
        let sa = base.assumingMemoryBound(to: sockaddr.self)
        switch Int32(sa.pointee.sa_family) {
        case AF_INET:
            var sin = base.assumingMemoryBound(to: sockaddr_in.self).pointee
            var addr = sin.sin_addr
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let c = inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
            let ip = c.map { String(cString: $0) } ?? "?"
            let port = Int(UInt16(bigEndian: sin.sin_port))
            return "\(ip):\(port)"
        case AF_INET6:
            var sin6 = base.assumingMemoryBound(to: sockaddr_in6.self).pointee
            var addr6 = sin6.sin6_addr
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            let c = inet_ntop(AF_INET6, &addr6, &buf, socklen_t(INET6_ADDRSTRLEN))
            let ip = c.map { String(cString: $0) } ?? "?"
            let port = Int(UInt16(bigEndian: sin6.sin6_port))
            return "[\(ip)]:\(port)"
        default:
            return nil
        }
    }
}

// MARK: - Public model

public struct DiscoveredHost: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let endpoint: NWEndpoint
    public init(name: String, endpoint: NWEndpoint) {
        self.name = name
        self.endpoint = endpoint
    }
}

// MARK: - Viewer: Browser (NWBrowser + NetServiceBrowser)

private let browserLog = Logger(subsystem: BeamConfig.subsystemViewer, category: "browser")

public final class BeamBrowser: NSObject, ObservableObject {
    @Published public private(set) var hosts: [DiscoveredHost] = []
    private var nwBrowser: NWBrowser?
    private var nsBrowser: NetServiceBrowser?
    private var nsServices: [NetService] = []
    private var aggregate: [String: DiscoveredHost] = [:]

    public override init() { super.init() }

    public func start() throws {
        guard nwBrowser == nil, nsBrowser == nil else { throw BeamError.alreadyRunning }

        Task { @MainActor in
            self.aggregate.removeAll()
            self.hosts.removeAll()
        }

        // A) NWBrowser (Network.framework Bonjour)
        let descriptor = NWBrowser.Descriptor.bonjour(type: BeamConfig.controlService, domain: nil)
        let params = BeamTransportParameters.tcpPeerToPeer()
        let nw = NWBrowser(for: descriptor, using: params)
        self.nwBrowser = nw

        BeamLog.info("Browser: start \(BeamConfig.controlService)", tag: "viewer")

        nw.stateUpdateHandler = { state in
            browserLog.debug("NWBrowser state: \(String(describing: state))")
            BeamLog.debug("Browser state=\(String(describing: state))", tag: "viewer")
            if case .failed(let err) = state {
                browserLog.error("NWBrowser failed: \(err.localizedDescription, privacy: .public)")
                BeamLog.error("Browser failed: \(err.localizedDescription)", tag: "viewer")
            }
        }

        nw.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            Task { @MainActor in
                var newAgg: [String: DiscoveredHost] = [:]
                for r in results {
                    let ep = r.endpoint
                    let name: String
                    if case let .service(name: svcName, type: _, domain: _, interface: _) = ep { name = svcName }
                    else { name = "Host" }
                    newAgg[ep.debugDescription] = DiscoveredHost(name: name, endpoint: ep)
                }
                self.aggregate = newAgg
                self.publishHosts()
                let names = newAgg.values.map { $0.name }.sorted().joined(separator: ", ")
                BeamLog.info("Browser results: \(names)", tag: "viewer")
            }
        }

        nw.start(queue: .main)

        // B) NetServiceBrowser (classic Bonjour) with address resolution logging
        let nsb = NetServiceBrowser()
        nsb.includesPeerToPeer = true
        nsb.delegate = self
        self.nsBrowser = nsb
        let typeToSearch = BeamConfig.controlService.hasSuffix(".") ? BeamConfig.controlService : BeamConfig.controlService + "."
        nsb.searchForServices(ofType: typeToSearch, inDomain: "local.")
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
        BeamLog.info("Browser: stopped", tag: "viewer")
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
        // Resolve addresses to log them (Wi-Fi vs AWDL)
        service.resolve(withTimeout: 5.0)

        let name = service.name
        let type = service.type.hasSuffix(".") ? String(service.type.dropLast()) : service.type
        let domain = service.domain.isEmpty ? "local." : service.domain
        let ep = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        Task { @MainActor in
            self.aggregate[ep.debugDescription] = DiscoveredHost(name: name, endpoint: ep)
            if !moreComing { self.publishHosts() }
        }
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        BeamLog.warn("NSResolve error: \(errorDict) for \(sender.name)", tag: "viewer")
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        let addrs = (sender.addresses ?? []).compactMap { renderSockaddr($0) }
        if addrs.isEmpty {
            BeamLog.info("Resolved \(sender.name) (no addresses)", tag: "viewer")
        } else {
            BeamLog.info("Resolved \(sender.name) → \(addrs.joined(separator: ", "))", tag: "viewer")
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
        BeamLog.error("NSBrowser error: \(errorDict)", tag: "viewer")
    }
}

// MARK: - Host control server

private let serverLog  = Logger(subsystem: BeamConfig.subsystemHost, category: "control-server")
private let bonjourLog = Logger(subsystem: BeamConfig.subsystemHost, category: "bonjour")

public struct PendingPair: Identifiable, Equatable {
    public let id = UUID()
    public let code: String
    public let receivedAt: Date
    public let remoteDescription: String
    fileprivate let connection: NWConnection
    public let connID: Int
    public static func == (lhs: PendingPair, rhs: PendingPair) -> Bool { lhs.id == rhs.id }
    public init(code: String, remoteDescription: String, connection: NWConnection, connID: Int) {
        self.code = code
        self.receivedAt = Date()
        self.remoteDescription = remoteDescription
        self.connection = connection
        self.connID = connID
    }
}

public struct ActiveSession: Identifiable, Equatable {
    public let id: UUID
    public let startedAt: Date
    public let remoteDescription: String
}

public final class BeamControlServer: NSObject, ObservableObject {
    // State
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var publishedName: String?
    @Published public private(set) var pendingPairs: [PendingPair] = []
    @Published public private(set) var sessions: [ActiveSession] = []

    // Networking
    private var listener: NWListener?
    private var netService: NetService?

    // Book-keeping
    private var pendingByID: [UUID: PendingPair] = [:]
    private var connections: [NWConnection] = []
    private var rxBuffers: [ObjectIdentifier: Data] = [:]
    private var connSeq: Int = 0
    private var connIDs: [ObjectIdentifier: Int] = [:]

    // Keepalive / heartbeat
    private var hbTimer: DispatchSourceTimer?
    private let hbInterval: TimeInterval = 5

    // Bonjour recovery
    private var bonjourName: String?
    private var bonjourBackoffAttempt: Int = 0

    public override init() { super.init() }

    private func cid(for conn: NWConnection) -> Int { connIDs[ObjectIdentifier(conn)] ?? -1 }

    @MainActor
    public func start(serviceName: String) throws {
        guard listener == nil else { throw BeamError.alreadyRunning }

        // Listener on fixed control port with P2P + TCP keepalives
        let params = BeamTransportParameters.tcpPeerToPeer()
        guard let port = NWEndpoint.Port(rawValue: BeamConfig.controlPort) else {
            throw BeamError.connectionFailed("Bad control port")
        }
        let l = try NWListener(using: params, on: port)
        self.listener = l

        l.stateUpdateHandler = { state in
            serverLog.debug("Listener state: \(String(describing: state))")
            BeamLog.debug("Host listener state=\(String(describing: state))", tag: "host")
            if case .failed(let err) = state {
                serverLog.error("Listener failed: \(err.localizedDescription, privacy: .public)")
                BeamLog.error("Host listener failed: \(err.localizedDescription)", tag: "host")
            }
        }

        l.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            Task { @MainActor in
                self.connSeq += 1
                let key = ObjectIdentifier(conn)
                self.connIDs[key] = self.connSeq
                let cid = self.connSeq
                let remote = conn.currentPath?.remoteEndpoint?.debugDescription ?? "peer"
                let ps = pathSummary(conn.currentPath)
                BeamLog.info("conn#\(cid) accepted (remote=\(remote), path=\(ps))", tag: "host")
                self.handleIncoming(conn)
            }
        }

        l.start(queue: .main)

        // Bonjour publish (classic API) w/ P2P
        let type = BeamConfig.controlService.hasSuffix(".") ? BeamConfig.controlService : BeamConfig.controlService + "."
        let ns = NetService(domain: "local.", type: type, name: serviceName, port: Int32(BeamConfig.controlPort))
        ns.includesPeerToPeer = true
        ns.delegate = self
        ns.publish()
        self.netService = ns
        self.publishedName = serviceName
        self.bonjourName = serviceName
        self.bonjourBackoffAttempt = 0

        // Start heartbeats
        startHeartbeats()

        self.isRunning = true
        serverLog.info("Control server started on \(BeamConfig.controlPort), bonjour '\(serviceName)'")
        BeamLog.info("Host advertising '\(serviceName)' \(BeamConfig.controlService) on \(BeamConfig.controlPort)", tag: "host")
    }

    @MainActor
    public func stop() {
        stopHeartbeats()
        netService?.stop(); netService = nil
        listener?.cancel(); listener = nil
        for c in connections { c.cancel() }
        connections.removeAll()
        rxBuffers.removeAll()
        pendingPairs.removeAll()
        pendingByID.removeAll()
        connIDs.removeAll()
        publishedName = nil
        isRunning = false
        serverLog.info("Control server stopped")
        BeamLog.info("Host stopped", tag: "host")
    }

    @MainActor
    public func accept(_ id: UUID) {
        guard let p = pendingByID.removeValue(forKey: id) else { return }
        pendingPairs.removeAll { $0.id == id }
        let sid = UUID()
        let resp = HandshakeResponse(ok: true, sessionID: sid, udpPort: nil, message: "OK")
        sendResponse(resp, over: p.connection)
        sessions.append(ActiveSession(id: sid, startedAt: Date(), remoteDescription: p.remoteDescription))
        BeamLog.info("conn#\(p.connID) ACCEPT code \(p.code) → session \(sid)", tag: "host")
    }

    @MainActor
    public func decline(_ id: UUID) {
        guard let p = pendingByID.removeValue(forKey: id) else { return }
        pendingPairs.removeAll { $0.id == id }
        let resp = HandshakeResponse(ok: false, sessionID: nil, udpPort: nil, message: "Declined")
        sendResponse(resp, over: p.connection)
        BeamLog.warn("conn#\(p.connID) DECLINE code \(p.code) from \(p.remoteDescription)", tag: "host")
        p.connection.cancel()
    }

    @MainActor
    private func handleIncoming(_ conn: NWConnection) {
        connections.append(conn)
        let key = ObjectIdentifier(conn)
        rxBuffers[key] = Data()
        let cid = self.cid(for: conn)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            let ps = pathSummary(conn.currentPath)
            BeamLog.debug("conn#\(cid) state=\(String(describing: state)) path=\(ps)", tag: "host")
            if case .failed(let err) = state {
                serverLog.error("Incoming failed: \(err.localizedDescription, privacy: .public)")
                BeamLog.error("conn#\(cid) failed: \(err.localizedDescription)", tag: "host")
            }
        }

        conn.start(queue: .main)
        receiveLoop(conn)
    }

    private func receiveLoop(_ conn: NWConnection) {
        let key = ObjectIdentifier(conn)
        let cid = self.cid(for: conn)

        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isEOF, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                Task { @MainActor in
                    BeamLog.debug("conn#\(cid) rx \(data.count) bytes", tag: "host")
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
                    BeamLog.warn("conn#\(cid) closed (EOF=\(isEOF), err=\(String(describing: error)))", tag: "host")
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
        let cid = self.cid(for: conn)

        // Heartbeat from peer
        if (try? JSONDecoder().decode(Heartbeat.self, from: line)) != nil {
            BeamLog.debug("conn#\(cid) hb", tag: "host")
            return
        }

        // Handshake
        if let req = try? JSONDecoder().decode(HandshakeRequest.self, from: line) {
            let remote = conn.currentPath?.remoteEndpoint?.debugDescription ?? "peer"

            if BeamConfig.autoAcceptDuringTest {
                let sid = UUID()
                let resp = HandshakeResponse(ok: true, sessionID: sid, udpPort: nil, message: "OK")
                sendResponse(resp, over: conn)
                sessions.append(ActiveSession(id: sid, startedAt: Date(), remoteDescription: remote))
                BeamLog.info("conn#\(cid) AUTO-ACCEPT code \(req.code) → session \(sid)", tag: "host")
                return
            }

            // Manual flow
            let p = PendingPair(code: req.code, remoteDescription: remote, connection: conn, connID: cid)
            pendingByID[p.id] = p
            pendingPairs.append(p)
            serverLog.info("Pending pair from \(remote, privacy: .public) code \(req.code, privacy: .public)")
            BeamLog.info("conn#\(cid) handshake code \(req.code) (pending=\(pendingPairs.count))", tag: "host")
            return
        }

        serverLog.error("Invalid line on control connection")
        BeamLog.error("conn#\(cid) invalid frame", tag: "host")
    }

    @MainActor
    private func sendResponse(_ resp: HandshakeResponse, over conn: NWConnection) {
        let cid = self.cid(for: conn)
        do {
            let bytes = try Frame.encodeLine(resp)
            conn.send(content: bytes, completion: .contentProcessed { _ in
                BeamLog.debug("conn#\(cid) sent \(bytes.count) bytes (response ok=\(resp.ok))", tag: "host")
            })
            if !resp.ok { conn.cancel() }
        } catch {
            serverLog.error("Failed to encode response: \(error.localizedDescription, privacy: .public)")
            BeamLog.error("conn#\(cid) send failed: \(error.localizedDescription)", tag: "host")
        }
    }

    // MARK: Heartbeats

    @MainActor
    private func startHeartbeats() {
        stopHeartbeats()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + hbInterval, repeating: hbInterval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            for c in self.connections {
                do {
                    let bytes = try Frame.encodeLine(Heartbeat())
                    let id = self.cid(for: c)
                    c.send(content: bytes, completion: .contentProcessed { _ in
                        BeamLog.debug("conn#\(id) sent \(bytes.count) bytes (hb)", tag: "host")
                    })
                } catch {
                    BeamLog.error("hb encode fail: \(error.localizedDescription)", tag: "host")
                }
            }
        }
        t.resume()
        hbTimer = t
    }

    @MainActor
    private func stopHeartbeats() {
        hbTimer?.cancel()
        hbTimer = nil
    }

    // MARK: Bonjour delegate w/ recovery

    private func scheduleBonjourRestart() {
        guard let name = bonjourName else { return }
        bonjourBackoffAttempt += 1
        let delay = min(pow(2.0, Double(bonjourBackoffAttempt - 1)), 30.0) // 1,2,4,8,16,30
        BeamLog.warn("Bonjour republish in \(Int(delay))s (attempt \(bonjourBackoffAttempt))", tag: "host")

        // Stop current, create a fresh NetService, publish after delay
        netService?.stop(); netService = nil
        let type = BeamConfig.controlService.hasSuffix(".") ? BeamConfig.controlService : BeamConfig.controlService + "."
        let ns = NetService(domain: "local.", type: type, name: name, port: Int32(BeamConfig.controlPort))
        ns.includesPeerToPeer = true
        ns.delegate = self
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.netService = ns
            ns.publish()
        }
    }
}

extension BeamControlServer: NetServiceDelegate {
    public func netServiceDidPublish(_ sender: NetService) {
        bonjourLog.info("Published \(sender.name, privacy: .public)")
        BeamLog.info("Bonjour published: \(sender.name)", tag: "host")
        bonjourBackoffAttempt = 0
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        bonjourLog.error("Publish error: \(String(describing: errorDict), privacy: .public)")
        BeamLog.error("Bonjour publish error: \(errorDict)", tag: "host")
        scheduleBonjourRestart()
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
    private var attemptSeq: Int = 0
    private var attemptID: Int = 0
    private var handshakeTimeoutTask: Task<Void, Never>?

    // Heartbeat
    private var hbTimer: DispatchSourceTimer?
    private let hbInterval: TimeInterval = 5

    public init() {}

    public static func randomCode() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }

    @MainActor
    public func connect(to host: DiscoveredHost, code: String) {
        // Ensure any prior attempt is fully torn down on the main actor
        disconnect()

        attemptSeq += 1
        attemptID = attemptSeq

        let hostName = host.name
        let remoteDesc = host.endpoint.debugDescription
        BeamLog.info("conn#\(attemptID) Connecting to \(hostName) @ \(remoteDesc) with code \(code)", tag: "viewer")

        let params = BeamTransportParameters.tcpPeerToPeer()
        let conn = NWConnection(to: host.endpoint, using: params)
        self.connection = conn

        self.status = .connecting(hostName: hostName, remote: remoteDesc)

        // Capture an immutable ID for logs inside handlers (which may run off the main actor)
        let idForLogs = attemptID

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            let ps = pathSummary(conn.currentPath)
            switch state {
            case .ready:
                clientLog.info("Control ready to \(hostName, privacy: .public)")
                BeamLog.info("conn#\(idForLogs) ready (path=\(ps)) → send handshake", tag: "viewer")
                Task { @MainActor in
                    self.sendHandshake(code: code)
                    self.receiveLoop()
                }
            case .failed(let err):
                BeamLog.error("conn#\(idForLogs) failed: \(err.localizedDescription) (path=\(ps))", tag: "viewer")
                Task { @MainActor in
                    self.handshakeTimeoutTask?.cancel()
                    self.stopHeartbeats()
                    self.status = .failed(reason: err.localizedDescription)
                    self.connection?.cancel()
                    self.connection = nil
                }
            case .cancelled:
                BeamLog.warn("conn#\(idForLogs) cancelled (path=\(ps))", tag: "viewer")
                Task { @MainActor in
                    self.handshakeTimeoutTask?.cancel()
                    self.stopHeartbeats()
                    if case .failed = self.status { /* keep failed */ }
                    else { self.status = .idle }
                }
            default:
                BeamLog.debug("conn#\(idForLogs) state=\(String(describing: state)) (path=\(ps))", tag: "viewer")
            }
        }

        conn.start(queue: .main)
    }

    @MainActor
    public func disconnect() {
        handshakeTimeoutTask?.cancel(); handshakeTimeoutTask = nil
        stopHeartbeats()
        connection?.cancel(); connection = nil
        rxBuffer.removeAll()
        status = .idle
        BeamLog.info("Disconnected", tag: "viewer")
    }

    @MainActor
    private func sendHandshake(code: String) {
        guard let conn = connection else { return }
        let req = HandshakeRequest(role: .viewer, code: code)
        do {
            let bytes = try Frame.encodeLine(req)
            status = .waitingAcceptance
            conn.send(content: bytes, completion: .contentProcessed { _ in
                BeamLog.debug("conn#\(self.attemptID) sent \(bytes.count) bytes (handshake)", tag: "viewer")
            })
            BeamLog.info("conn#\(attemptID) handshake sent (\(bytes.count) bytes, code \(code))", tag: "viewer")

            // Timeout if Host doesn't accept shortly (helps see stalls)
            handshakeTimeoutTask?.cancel()
            handshakeTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    if case .waitingAcceptance = self.status {
                        BeamLog.warn("conn#\(self.attemptID) WAIT TIMEOUT (no Host accept)", tag: "viewer")
                    }
                }
            }
        } catch {
            status = .failed(reason: "Encode failed")
            conn.cancel()
            BeamLog.error("conn#\(attemptID) encode fail: \(error.localizedDescription)", tag: "viewer")
        }
    }

    private func receiveLoop() {
        guard let conn = connection else { return }
        let id = attemptID

        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isEOF, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                BeamLog.debug("conn#\(id) rx \(data.count) bytes", tag: "viewer")
                for line in Frame.drainLines(buffer: &self.rxBuffer, incoming: data) {
                    self.handleLine(line)
                }
            }

            if isEOF || error != nil {
                Task { @MainActor in
                    self.handshakeTimeoutTask?.cancel()
                    self.stopHeartbeats()
                    if case .paired = self.status {
                        // Keep paired display if peer closed intentionally; otherwise mark failure
                    } else if case .failed = self.status {
                        // keep failed
                    } else {
                        self.status = .failed(reason: "Disconnected")
                    }
                    self.connection?.cancel(); self.connection = nil
                }
                BeamLog.warn("conn#\(id) closed (EOF=\(isEOF), err=\(String(describing: error)))", tag: "viewer")
                return
            }

            self.receiveLoop()
        }
    }

    private func handleLine(_ line: Data) {
        // Heartbeat from host
        if (try? JSONDecoder().decode(Heartbeat.self, from: line)) != nil {
            BeamLog.debug("hb ✓", tag: "viewer")
            return
        }

        if let resp = try? JSONDecoder().decode(HandshakeResponse.self, from: line) {
            Task { @MainActor in
                self.handshakeTimeoutTask?.cancel()
                if resp.ok, let sid = resp.sessionID {
                    self.status = .paired(session: sid, udpPort: resp.udpPort)
                    BeamLog.info("Paired ✓ session=\(sid)", tag: "viewer")
                    self.startHeartbeats() // begin viewer→host heartbeats after pairing
                } else {
                    let reason = resp.message ?? "Rejected"
                    self.status = .failed(reason: reason)
                    BeamLog.warn("Pairing rejected: \(reason)", tag: "viewer")
                }
            }
            return
        }

        BeamLog.error("Viewer received invalid response frame", tag: "viewer")
    }

    // MARK: Heartbeats

    @MainActor
    private func startHeartbeats() {
        stopHeartbeats()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + hbInterval, repeating: hbInterval)
        t.setEventHandler { [weak self] in
            guard let self, let c = self.connection else { return }
            do {
                let bytes = try Frame.encodeLine(Heartbeat())
                c.send(content: bytes, completion: .contentProcessed { _ in
                    BeamLog.debug("hb → sent", tag: "viewer")
                })
            } catch {
                BeamLog.error("hb encode fail: \(error.localizedDescription)", tag: "viewer")
            }
        }
        t.resume()
        hbTimer = t
    }

    @MainActor
    private func stopHeartbeats() {
        hbTimer?.cancel()
        hbTimer = nil
    }
}

// MARK: - Transport Parameter presets

fileprivate enum BeamTransportParameters {
    /// TCP parameters with peer-to-peer enabled and TCP keepalives configured
    static func tcpPeerToPeer() -> NWParameters {
        // Configure TCP keepalives (defaults are disabled)
        // Ref: NWProtocolTCP.Options.enableKeepalive / keepaliveIdle / keepaliveInterval
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10      // seconds of idle before probes
        tcp.keepaliveInterval = 5   // seconds between probes
        // You can tweak keepaliveCount if desired:
        // tcp.keepaliveCount = 3

        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true // required for AWDL / P2P Wi-Fi
        return params
    }
}

// MARK: - Sendable shims

extension BeamBrowser: @unchecked Sendable {}
extension BeamControlServer: @unchecked Sendable {}
extension BeamControlClient: @unchecked Sendable {}
