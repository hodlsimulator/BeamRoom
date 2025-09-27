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
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
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
                case .ready:
                    BeamLog.info("Host listener state=ready", tag: "host")
                case .failed(let err):
                    BeamLog.error("Host listener failed: \(err.localizedDescription)", tag: "host")
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
                Task { @MainActor in
                    guard let self else { return }
                    self.udpPeer = peer
                    // Auto-start/stop the M3 test stream based on peer presence during test mode.
                    if peer == nil {
                        if self.isStreaming {
                            self.stopTestStream()
                        }
                    } else {
                        if BeamConfig.autoAcceptDuringTest && !self.isStreaming {
                            self.startTestStream()
                        }
                    }
                }
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
        BeamLog.info("Test stream START requested (UI/auto)", tag: "host")
        media.startTestFrames()
        isStreaming = true
    }

    public func stopTestStream() {
        BeamLog.info("Test stream STOP requested (UI/auto)", tag: "host")
        media?.stopTestFrames()
        isStreaming = false
    }

    // MARK: Internal utilities (internal so Conn can call them from another file)

    func acceptConnection(_ conn: Conn, code: String) {
        // Idempotent: if this connection already has a session, just re-ack and push state.
        if let existing = conn.sessionID {
            conn.sendHandshake(ok: true, sessionID: existing, message: "Already paired", udpPort: BeamConfig.getBroadcastUDPPort())
            if let udp = BeamConfig.getBroadcastUDPPort() { conn.sendMediaParams(udpPort: udp) }
            conn.sendBroadcast(hasOn: BeamConfig.isBroadcastOn())
            return
        }

        if let pid = conn.pendingPairID { removePending(pid) }

        let sid = UUID()
        conn.sessionID = sid
        sessions.append(ActiveSession(id: sid, remoteDescription: conn.remoteDescription, startedAt: Date()))

        // Handshake response with udpPort if known
        let udpPort = BeamConfig.getBroadcastUDPPort()
        conn.sendHandshake(ok: true, sessionID: sid, message: nil, udpPort: udpPort)
        if let udp = udpPort { conn.sendMediaParams(udpPort: udp) }
        conn.sendBroadcast(hasOn: BeamConfig.isBroadcastOn())
    }

    func queuePending(for conn: Conn, code: String) {
        // De-dupe: drop any earlier pending row tied to this connection.
        if let old = conn.pendingPairID {
            pendingPairs.removeAll { $0.id == old }
        }
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

    func connectionClosed(_ conn: Conn) {
        if let sid = conn.sessionID { sessions.removeAll { $0.id == sid } }
        if let pid = conn.pendingPairID { pendingPairs.removeAll { $0.id == pid } }
        connections.removeValue(forKey: conn.id)
    }

    private func findConn(for pendingID: UUID) -> Conn? {
        for (_, c) in connections where c.pendingPairID == pendingID {
            return c
        }
        return nil
    }

    private func removePending(_ id: UUID) {
        pendingPairs.removeAll { $0.id == id }
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
