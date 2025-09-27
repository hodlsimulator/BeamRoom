//
//  BeamControlServer.swift
//  BeamCore
//
//  Created by . . on 9/22/25.
//
//  Host-side TCP control server + Bonjour + UDP media (port announce + test stream)
//

import Foundation
import Combine
import Network
import OSLog

private let serverLog = Logger(subsystem: BeamConfig.subsystemHost, category: "control-server")

@MainActor
public final class BeamControlServer: NSObject, ObservableObject {

    // MARK: View-facing models
    public struct PendingPair: Identifiable, Equatable {
        public let id: UUID
        public let connID: Int
        public let code: String
        public let remoteDescription: String
        public let requestedAt: Date
    }
    public struct ActiveSession: Identifiable, Equatable {
        public let id: UUID
        public let remoteDescription: String
        public let startedAt: Date
    }

    // MARK: Published state
    @Published public private(set) var sessions: [ActiveSession] = []
    @Published public private(set) var pendingPairs: [PendingPair] = []
    @Published public private(set) var udpPeer: String? = nil
    @Published public private(set) var isStreaming: Bool = false

    // MARK: Configuration
    public var autoAccept: Bool

    // MARK: Internals
    private var listener: NWListener?
    private var netService: NetService?
    private var netServiceDelegateProxy: NetServiceDelegateProxy?
    private var republishAttempts = 0

    private var connections: [Int : Conn] = [:]
    private var nextConnID = 1

    // Broadcast poll → push to clients when it changes
    private var lastBroadcastOn: Bool = BeamConfig.isBroadcastOn()
    private var broadcastPoll: DispatchSourceTimer?

    // UDP media
    private var media: MediaUDP?

    public init(autoAccept: Bool = false) {
        self.autoAccept = autoAccept
        super.init()
    }

    // MARK: Lifecycle

    public func start(serviceName: String) throws {
        guard listener == nil else { throw BeamError.alreadyRunning }

        // TCP listener restricted to infrastructure Wi-Fi
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = false
        params.requiredInterfaceType = .wifi
        params.prohibitedInterfaceTypes = [.cellular]

        let port = NWEndpoint.Port(rawValue: BeamConfig.controlPort)!
        let lis = try NWListener(using: params, on: port)
        listener = lis

        lis.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                serverLog.debug("Listener state \(String(describing: state))")
                switch state {
                case .ready:  BeamLog.info("Host listener state=ready", tag: "host")
                case .failed(let err): BeamLog.error("Host listener failed: \(err.localizedDescription)", tag: "host")
                default: break
                }
            }
        }
        lis.newConnectionHandler = { [weak self] nw in
            Task { @MainActor in
                guard let self else { return }
                let id = self.nextConnID; self.nextConnID += 1
                let c = Conn(id: id, nw: nw, server: self)
                self.connections[id] = c
                c.start()
            }
        }
        lis.start(queue: .main)

        // Bonjour publish
        publishBonjour(name: serviceName, type: BeamConfig.controlService, port: Int(BeamConfig.controlPort))

        // UDP media (listener + peer capture)
        let media = MediaUDP(
            onPeerChanged: { [weak self] peer in
                Task { @MainActor in self?.udpPeer = peer }
            }
        )
        self.media = media
        media.start(
            onReady: { [weak self] udpPort in
                Task { @MainActor in
                    guard let self else { return }
                    BeamLog.info("Media UDP ready on port \(udpPort)", tag: "host")
                    BeamConfig.setBroadcastUDPPort(udpPort)
                    // Push MediaParams to all paired clients
                    for conn in self.connections.values where conn.sessionID != nil {
                        conn.sendMediaParams(udpPort: udpPort)
                    }
                }
            },
            onError: { err in
                Task { @MainActor in
                    BeamLog.error("Media UDP failed: \(err.localizedDescription)", tag: "host")
                }
            }
        )

        // Broadcast poll → inform all clients live
        startBroadcastPoll()
        BeamLog.info("Host advertising '\(serviceName)' \(BeamConfig.controlService) on \(BeamConfig.controlPort)", tag: "host")
    }

    public func stop() {
        stopBroadcastPoll()
        media?.stop(); media = nil
        isStreaming = false
        udpPeer = nil

        // Close children first
        for (_, c) in connections { c.close() }
        connections.removeAll()

        listener?.cancel(); listener = nil
        unpublishBonjour()
    }

    // MARK: Accept / Decline from UI

    public func accept(_ pendingID: UUID) {
        guard let conn = findConn(for: pendingID) else { return }
        acceptConnection(conn, code: conn.pendingCode ?? "----")
    }

    public func decline(_ pendingID: UUID) {
        guard let conn = findConn(for: pendingID) else { return }
        removePending(pendingID)
        conn.sendHandshake(ok: false, sessionID: nil, message: "Declined", udpPort: nil)
        conn.close()
    }

    // MARK: Test stream control (M3)

    public func startTestStream() {
        guard let media else { return }
        media.startTestFrames()
        isStreaming = true
    }

    public func stopTestStream() {
        media?.stopTestFrames()
        isStreaming = false
    }

    // MARK: Internal utilities

    fileprivate func acceptConnection(_ conn: Conn, code: String) {
        // Idempotent: if this connection already has a session, just re-ack and push state.
        if let existing = conn.sessionID {
            conn.sendHandshake(ok: true, sessionID: existing, message: "Already paired", udpPort: BeamConfig.getBroadcastUDPPort())
            if let udp = BeamConfig.getBroadcastUDPPort() { conn.sendMediaParams(udpPort: udp) }
            conn.sendBroadcast(hasOn: BeamConfig.isBroadcastOn())
            return
        }

        if let pid = conn.pendingPairID { removePending(pid) }
        let sid = UUID(); conn.sessionID = sid
        sessions.append(ActiveSession(id: sid, remoteDescription: conn.remoteDescription, startedAt: Date()))

        // Handshake response with udpPort if known
        let udpPort = BeamConfig.getBroadcastUDPPort()
        conn.sendHandshake(ok: true, sessionID: sid, message: nil, udpPort: udpPort)
        if let udp = udpPort { conn.sendMediaParams(udpPort: udp) }
        conn.sendBroadcast(hasOn: BeamConfig.isBroadcastOn())
    }

    private func findConn(for pendingID: UUID) -> Conn? {
        for (_, c) in connections where c.pendingPairID == pendingID { return c }
        return nil
    }
    private func removePending(_ id: UUID) { pendingPairs.removeAll { $0.id == id } }

    fileprivate func queuePending(for conn: Conn, code: String) {
        // De-dupe: drop any earlier pending row tied to this connection.
        if let old = conn.pendingPairID { pendingPairs.removeAll { $0.id == old } }
        let p = PendingPair(
            id: UUID(),
            connID: conn.id,
            code: code,
            remoteDescription: conn.remoteDescription,
            requestedAt: Date()
        )
        conn.pendingPairID = p.id
        conn.pendingCode = code
        pendingPairs.append(p)
    }

    fileprivate func connectionClosed(_ conn: Conn) {
        if let sid = conn.sessionID { sessions.removeAll { $0.id == sid } }
        if let pid = conn.pendingPairID { pendingPairs.removeAll { $0.id == pid } }
        connections.removeValue(forKey: conn.id)
    }

    // MARK: Bonjour

    private func publishBonjour(name: String, type: String, port: Int) {
        unpublishBonjour()
        let svcType = type.hasSuffix(".") ? type : type + "."
        let ns = NetService(domain: "local.", type: svcType, name: name, port: Int32(port))
        ns.includesPeerToPeer = true

        // Use a proxy to avoid having the @MainActor class conform to NetServiceDelegate.
        let proxy = NetServiceDelegateProxy(
            onPublished: { [weak self] sender in
                Task { @MainActor in
                    BeamLog.info("Bonjour published: \(sender.name)", tag: "host")
                    self?.republishAttempts = 0
                }
            },
            onDidNotPublish: { [weak self] sender, errorDict in
                Task { @MainActor in
                    guard let self else { return }
                    BeamLog.error("Bonjour publish error: \(errorDict)", tag: "host")
                    self.republishAttempts += 1
                    BeamLog.warn("Bonjour republish in 1s (attempt \(self.republishAttempts))", tag: "host")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    sender.stop()
                    self.netService = nil
                    self.publishBonjour(name: sender.name, type: sender.type, port: Int(sender.port))
                }
            }
        )
        netServiceDelegateProxy = proxy
        ns.delegate = proxy
        self.netService = ns
        ns.publish()
        republishAttempts = 0
    }

    private func unpublishBonjour() {
        netService?.stop()
        netService?.delegate = nil
        netService = nil
        netServiceDelegateProxy = nil
    }

    // MARK: Broadcast poll

    private func startBroadcastPoll() {
        stopBroadcastPoll()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let on = BeamConfig.isBroadcastOn()
                if on != self.lastBroadcastOn {
                    self.lastBroadcastOn = on
                    for conn in self.connections.values where conn.sessionID != nil {
                        conn.sendBroadcast(hasOn: on)
                    }
                }
            }
        }
        t.resume()
        broadcastPoll = t
    }

    private func stopBroadcastPoll() {
        broadcastPoll?.cancel()
        broadcastPoll = nil
    }
}

// MARK: - NetServiceDelegate proxy (non-actor, forwards to MainActor)

private final class NetServiceDelegateProxy: NSObject, NetServiceDelegate {
    typealias PublishedHandler = (NetService) -> Void
    typealias DidNotPublishHandler = (NetService, [String : NSNumber]) -> Void
    private let onPublished: PublishedHandler?
    private let onDidNotPublish: DidNotPublishHandler?
    init(onPublished: PublishedHandler?, onDidNotPublish: DidNotPublishHandler?) {
        self.onPublished = onPublished
        self.onDidNotPublish = onDidNotPublish
        super.init()
    }
    func netServiceDidPublish(_ sender: NetService) { onPublished?(sender) }
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) { onDidNotPublish?(sender, errorDict) }
}

// MARK: - Per-connection wrapper (TCP control)

@MainActor
private final class Conn {
    let id: Int
    let nw: NWConnection
    weak var server: BeamControlServer?
    var rxBuffer = Data()
    var hbTimer: DispatchSourceTimer?
    var pendingPairID: UUID?
    var pendingCode: String?
    var sessionID: UUID?

    var remoteDescription: String { nw.endpoint.debugDescription }

    init(id: Int, nw: NWConnection, server: BeamControlServer) {
        self.id = id
        self.nw = nw
        self.server = server
    }

    func start() {
        nw.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                let ps = pathSummary(self.nw.currentPath)
                switch state {
                case .preparing:
                    BeamLog.debug("conn#\(self.id) state=preparing path=\(ps)", tag: "host")
                case .ready:
                    BeamLog.debug("conn#\(self.id) state=ready path=\(ps)", tag: "host")
                    BeamLog.info("conn#\(self.id) accepted (remote=\(self.remoteDescription), path=\(ps))", tag: "host")
                    self.receiveLoop()
                    self.startHeartbeats()
                case .failed(let err):
                    BeamLog.error("conn#\(self.id) failed: \(err.localizedDescription)", tag: "host")
                    self.close()
                case .cancelled:
                    BeamLog.warn("conn#\(self.id) state=cancelled path=-", tag: "host")
                default: break
                }
            }
        }
        nw.start(queue: .main)
    }

    func close() {
        stopHeartbeats()
        nw.cancel()
        server?.connectionClosed(self)
    }

    private func receiveLoop() {
        nw.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isEOF, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty {
                    for line in Frame.drainLines(buffer: &self.rxBuffer, incoming: data) {
                        self.handleLine(line)
                    }
                }
                if isEOF || error != nil {
                    BeamLog.warn("conn#\(self.id) closed (EOF=\(isEOF), err=\(String(describing: error)))", tag: "host")
                    self.close()
                    return
                }
                self.receiveLoop()
            }
        }
    }

    private func handleLine(_ line: Data) {
        // 1) Handshake (Viewer → Host)
        if let req = try? JSONDecoder().decode(HandshakeRequest.self, from: line) {
            // Only accept Viewer role
            guard req.role.rawValue == "viewer" else {
                sendHandshake(ok: false, sessionID: nil, message: "Invalid role", udpPort: nil)
                return
            }
            // If already paired, just acknowledge with the existing session
            if let sid = sessionID {
                sendHandshake(ok: true, sessionID: sid, message: "Already paired", udpPort: BeamConfig.getBroadcastUDPPort())
                if let udp = BeamConfig.getBroadcastUDPPort() { sendMediaParams(udpPort: udp) }
                sendBroadcast(hasOn: BeamConfig.isBroadcastOn())
                return
            }
            // Queue for accept, or auto-accept in test mode
            if let server, server.autoAccept {
                BeamLog.info("conn#\(id) AUTO-ACCEPT code \(req.code)", tag: "host")
                server.acceptConnection(self, code: req.code)
            } else {
                BeamLog.info("conn#\(id) handshake code \(req.code) (pending=1)", tag: "host")
                server?.queuePending(for: self, code: req.code)
                // Viewer has a timeout; no immediate reply here.
            }
            return
        }

        // 2) Heartbeat (Viewer → Host)
        if (try? JSONDecoder().decode(Heartbeat.self, from: line)) != nil {
            BeamLog.debug("conn#\(id) hb", tag: "host")
            return
        }

        // Unknown frame – ignore (keeps protocol resilient)
    }

    // MARK: Sending helpers

    func sendHandshake(ok: Bool, sessionID: UUID?, message: String?, udpPort: UInt16?) {
        let resp = HandshakeResponse(ok: ok, sessionID: sessionID, udpPort: udpPort, message: message)
        send(resp, note: "response ok=\(ok)")
    }

    func sendBroadcast(hasOn on: Bool) {
        let payload = BroadcastStatus(on: on)
        do {
            let bytes = try Frame.encodeLine(payload)
            nw.send(content: bytes, completion: .contentProcessed { _ in
                BeamLog.debug("conn#\(self.id) sent 13 bytes (broadcast=\(on))", tag: "host")
            })
        } catch {
            BeamLog.error("conn#\(id) send encode fail: \(error.localizedDescription)", tag: "host")
        }
    }

    func sendMediaParams(udpPort: UInt16) {
        send(MediaParams(udpPort: udpPort), note: "mediaParams udp=\(udpPort)")
    }

    private func send<T: Encodable>(_ payload: T, note: String) {
        do {
            let bytes = try Frame.encodeLine(payload)
            nw.send(content: bytes, completion: .contentProcessed { _ in /* small & frequent; skip log */ })
            if payload is HandshakeResponse {
                BeamLog.debug("conn#\(self.id) sent 78 bytes (\(note))", tag: "host")
            }
        } catch {
            BeamLog.error("conn#\(id) send encode fail: \(error.localizedDescription)", tag: "host")
        }
    }

    // MARK: Heartbeats

    private func startHeartbeats() {
        stopHeartbeats()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 2, repeating: 5)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            do {
                let bytes = try Frame.encodeLine(Heartbeat())
                self.nw.send(content: bytes, completion: .contentProcessed { _ in
                    BeamLog.debug("conn#\(self.id) sent 9 bytes (hb)", tag: "host")
                })
            } catch {
                BeamLog.error("hb encode fail: \(error.localizedDescription)", tag: "host")
            }
        }
        t.resume()
        hbTimer = t
    }

    private func stopHeartbeats() {
        hbTimer?.cancel()
        hbTimer = nil
    }
}

// MARK: - UDP media listener + test frame sender

// We keep MediaUDP on the main queue only; mark as @unchecked Sendable to appease @Sendable closures.
private final class MediaUDP: @unchecked Sendable {

    private var listener: NWListener?
    private var activePeer: NWConnection?
    private var peerDesc: String? { activePeer?.endpoint.debugDescription }
    private var onPeerChanged: ((String?) -> Void)?

    // Test stream
    private var streamTimer: DispatchSourceTimer?
    private var seq: UInt32 = 0
    private let w = 320, h = 180

    init(onPeerChanged: ((String?) -> Void)? = nil) {
        self.onPeerChanged = onPeerChanged
    }

    func start(
        onReady: @Sendable @escaping (UInt16) -> Void,
        onError: @Sendable @escaping (Error) -> Void
    ) {
        do {
            let params = NWParameters.udp
            params.requiredInterfaceType = .wifi
            params.includePeerToPeer = false

            // Use the port-less initializer; the system assigns an ephemeral port.
            let lis = try NWListener(using: params)
            listener = lis

            lis.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let p = self?.listener?.port?.rawValue {
                        onReady(p)
                    }
                case .failed(let err):
                    onError(err)
                default: break
                }
            }

            // Incoming UDP “connections” represent remote addresses that send us a datagram.
            lis.newConnectionHandler = { [weak self] conn in
                self?.installPeer(conn)
            }

            lis.start(queue: .main)
        } catch {
            onError(error)
        }
    }

    func stop() {
        stopTestFrames()
        activePeer?.cancel(); activePeer = nil
        listener?.cancel(); listener = nil
        onPeerChanged?(nil)
    }

    // MARK: Peer

    private func installPeer(_ conn: NWConnection) {
        // Replace any existing peer
        activePeer?.cancel()
        activePeer = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                BeamLog.info("UDP peer ready: \(conn.endpoint.debugDescription)", tag: "host")
                self.onPeerChanged?(conn.endpoint.debugDescription)
                self.receiveLoop(on: conn) // we don't need payload; just keep it alive
            case .failed(let err):
                BeamLog.error("UDP peer failed: \(err.localizedDescription)", tag: "host")
                self.onPeerChanged?(nil)
            case .cancelled:
                BeamLog.warn("UDP peer cancelled", tag: "host")
                self.onPeerChanged?(nil)
            default: break
            }
        }
        conn.start(queue: .main)
    }

    private func receiveLoop(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, _ in
            // Any datagram from the viewer is effectively a “hello”; ignore contents.
            if let self, let d = data, !d.isEmpty {
                BeamLog.debug("UDP ← \(d.count) bytes (hello/keepalive)", tag: "host")
            }
            self?.receiveLoop(on: conn)
        }
    }

    // MARK: Test frames

    func startTestFrames() {
        stopTestFrames()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.1, repeating: 1.0 / 12.0) // ~12 fps
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        streamTimer = t
    }

    func stopTestFrames() {
        streamTimer?.cancel()
        streamTimer = nil
    }

    private func tick() {
        guard let peer = activePeer else { return }
        seq &+= 1
        let payload = makeGradientFrame(seq: seq, w: w, h: h)
        peer.send(content: payload, completion: .contentProcessed { _ in
            BeamLog.debug("UDP → frame seq=\(self.seq) bytes=\(payload.count)", tag: "host")
        })
    }

    private func makeGradientFrame(seq: UInt32, w: Int, h: Int) -> Data {
        var out = Data(capacity: 12 + w*h*4)
        // Header
        out.appendBE(UInt32(0x424D524D)) // 'BMRM'
        out.appendBE(seq)
        out.appendBE(UInt16(w))
        out.appendBE(UInt16(h))
        // Pixels (BGRA32): simple moving gradient
        out.reserveCapacity(12 + w*h*4)
        let t = Double(seq) * 0.08
        for y in 0..<h {
            let gy = UInt8((Double(y) / Double(h)) * 255.0)
            for x in 0..<w {
                let rx = UInt8((Double(x) / Double(w)) * 255.0)
                let s = UInt8((sin((Double(x)+Double(y))*0.05 + t) * 0.5 + 0.5) * 255.0)
                // B, G, R, A
                out.append(s)    // B
                out.append(gy)   // G
                out.append(rx)   // R
                out.append(255)  // A
            }
        }
        return out
    }
}

// MARK: - Helpers

private extension Data {
    // Write integers in big-endian without unsafe pointer gymnastics.
    mutating func appendBE<T: FixedWidthInteger>(_ v: T) {
        for i in (0..<MemoryLayout<T>.size).reversed() {
            let byte = UInt8(truncatingIfNeeded: (v >> (i * 8)))
            append(byte)
        }
    }
}
