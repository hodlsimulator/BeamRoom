//
//  BeamControlServer.swift
//  BeamCore
//
//  Created by . . on 9/22/25.
//

import Foundation
import Network
import OSLog

private let serverLog = Logger(subsystem: BeamConfig.subsystemHost, category: "control-server")
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
    // UI state
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

    // Heartbeats (outbound from host)
    private var hbTimer: DispatchSourceTimer?
    private let hbInterval: TimeInterval = 5

    // Bonjour recovery
    private var bonjourName: String?
    private var bonjourBackoffAttempt: Int = 0

    // Liveness diagnostics (inbound from viewer)
    private var livenessTimer: DispatchSourceTimer?
    private let livenessGrace: TimeInterval = 15
    private var lastRxAtByConn: [ObjectIdentifier: Date] = [:]

    // Auto-accept control (toggle from UI)
    public var autoAccept: Bool

    public init(autoAccept: Bool = BeamConfig.autoAcceptDuringTest) {
        self.autoAccept = autoAccept
        super.init()
    }

    private func cid(for conn: NWConnection) -> Int { connIDs[ObjectIdentifier(conn)] ?? -1 }

    // MARK: Start/stop

    @MainActor
    public func start(serviceName: String) throws {
        guard listener == nil else { throw BeamError.alreadyRunning }

        // ⬅︎ Force infra Wi-Fi for the listener (no AWDL/cellular)
        let params = BeamTransportParameters.tcpInfraWiFi()
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

                // Path + viability diagnostics
                conn.viabilityUpdateHandler = { isViable in
                    BeamLog.debug("conn#\(cid) viable=\(isViable)", tag: "host")
                }
                conn.betterPathUpdateHandler = { hasBetter in
                    BeamLog.debug("conn#\(cid) betterPath=\(hasBetter)", tag: "host")
                }
                conn.pathUpdateHandler = { path in
                    BeamLog.debug("conn#\(cid) pathUpdate=\(pathSummary(path))", tag: "host")
                }

                // Seed liveness timestamp so we don’t instantly trip before first rx
                self.lastRxAtByConn[key] = Date()
                self.handleIncoming(conn)
            }
        }

        l.start(queue: .main)

        // Publish Bonjour (classic)
        let type = BeamConfig.controlService.hasSuffix(".") ? BeamConfig.controlService : BeamConfig.controlService + "."
        let ns = NetService(domain: "local.", type: type, name: serviceName, port: Int32(BeamConfig.controlPort))
        ns.includesPeerToPeer = true
        ns.delegate = self
        ns.publish()
        self.netService = ns

        self.publishedName = serviceName
        self.bonjourName = serviceName
        self.bonjourBackoffAttempt = 0

        startHeartbeats()
        startLivenessWatch()
        self.isRunning = true

        serverLog.info("Control server started on \(BeamConfig.controlPort), bonjour '\(serviceName)'")
        BeamLog.info("Host advertising '\(serviceName)' \(BeamConfig.controlService) on \(BeamConfig.controlPort)", tag: "host")
    }

    @MainActor
    public func stop() {
        stopHeartbeats()
        stopLivenessWatch()
        netService?.stop(); netService = nil
        listener?.cancel(); listener = nil

        for c in connections { c.cancel() }
        connections.removeAll()
        rxBuffers.removeAll()
        lastRxAtByConn.removeAll()
        pendingPairs.removeAll()
        pendingByID.removeAll()
        connIDs.removeAll()

        publishedName = nil
        isRunning = false
        serverLog.info("Control server stopped")
        BeamLog.info("Host stopped", tag: "host")
    }

    // MARK: UI actions

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

    // MARK: Connection handling

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
                    // Liveness: any inbound traffic refreshes the timestamp
                    self.lastRxAtByConn[key] = Date()

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
                    self.lastRxAtByConn.removeValue(forKey: key)
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

        // 1) Handshake
        if let req = try? JSONDecoder().decode(HandshakeRequest.self, from: line) {
            let remote = conn.currentPath?.remoteEndpoint?.debugDescription ?? "peer"
            if self.autoAccept {
                let sid = UUID()
                let resp = HandshakeResponse(ok: true, sessionID: sid, udpPort: nil, message: "OK")
                sendResponse(resp, over: conn)
                sessions.append(ActiveSession(id: sid, startedAt: Date(), remoteDescription: remote))
                BeamLog.info("conn#\(cid) AUTO-ACCEPT code \(req.code) → session \(sid)", tag: "host")
                return
            }
            let p = PendingPair(code: req.code, remoteDescription: remote, connection: conn, connID: cid)
            pendingByID[p.id] = p
            pendingPairs.append(p)
            serverLog.info("Pending pair from \(remote, privacy: .public) code \(req.code, privacy: .public)")
            BeamLog.info("conn#\(cid) handshake code \(req.code) (pending=\(pendingPairs.count))", tag: "host")
            return
        }

        // 2) Heartbeat
        if (try? JSONDecoder().decode(Heartbeat.self, from: line)) != nil {
            BeamLog.debug("conn#\(cid) hb", tag: "host")
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

    // MARK: Heartbeats (host → viewers)

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

    // MARK: Liveness diagnostics (viewer → host)

    @MainActor
    private func startLivenessWatch() {
        stopLivenessWatch()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + livenessGrace, repeating: livenessGrace)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date()
            for c in self.connections {
                let key = ObjectIdentifier(c)
                let last = self.lastRxAtByConn[key] ?? now
                let gap = now.timeIntervalSince(last)
                if gap > self.livenessGrace {
                    let id = self.cid(for: c)
                    BeamLog.warn("LIVENESS: no viewer traffic on conn#\(id) for \(Int(gap))s; closing", tag: "host")
                    self.lastRxAtByConn.removeValue(forKey: key)
                    c.cancel()
                    self.connections.removeAll { $0 === c }
                    self.rxBuffers.removeValue(forKey: key)
                }
            }
        }
        t.resume()
        livenessTimer = t
    }

    @MainActor
    private func stopLivenessWatch() {
        livenessTimer?.cancel()
        livenessTimer = nil
    }
}

// MARK: Bonjour delegate + recovery
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

    private func scheduleBonjourRestart() {
        guard let name = bonjourName else { return }
        bonjourBackoffAttempt += 1
        let delay = min(pow(2.0, Double(bonjourBackoffAttempt - 1)), 30.0) // 1,2,4,8,16,30
        BeamLog.warn("Bonjour republish in \(Int(delay))s (attempt \(bonjourBackoffAttempt))", tag: "host")

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
