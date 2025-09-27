//
//  BeamControlClient.swift
//  BeamCore
//
//  Created by . . on 9/22/25.
//

import Foundation
import Network
import OSLog

private let clientLog = Logger(subsystem: BeamConfig.subsystemViewer, category: "control-client")

@MainActor
public final class BeamControlClient: ObservableObject {

    public enum Status: Equatable {
        case idle
        case connecting(hostName: String, remote: String)
        case waitingAcceptance
        case paired(session: UUID, udpPort: UInt16?)
        case failed(reason: String)
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var broadcastOn: Bool = BeamConfig.isBroadcastOn() // latest known from Host

    private var connection: NWConnection?
    private var rxBuffer = Data()

    private var attemptSeq: Int = 0
    private var attemptID: Int = 0
    private var handshakeTimeoutTask: Task<Void, Never>?   // ← fix: add generic parameters

    // Heartbeat (app-level)
    private var hbTimer: DispatchSourceTimer?
    private let hbInterval: TimeInterval = 5

    // Liveness diagnostics
    private var lastRxAt: Date?
    private var livenessTimer: DispatchSourceTimer?
    private let livenessGrace: TimeInterval = 15

    public init() {}

    public static func randomCode() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }

    // MARK: Lifecycle

    @MainActor
    public func connect(to host: DiscoveredHost, code: String) {
        // Debounce: ignore while connecting/waiting/paired
        switch status {
        case .idle, .failed:
            break
        default:
            BeamLog.warn("connect() ignored; status=\(String(describing: status))", tag: "viewer")
            return
        }

        // Tear down any prior attempt
        disconnect()

        attemptSeq += 1
        attemptID = attemptSeq

        let endpoint = host.connectEndpoint
        let hostName = host.name
        let remoteDesc = endpoint.debugDescription

        BeamLog.info("conn#\(attemptID) Connecting to \(hostName) @ \(remoteDesc) with code \(code)", tag: "viewer")

        // ⬅︎ Force infra Wi-Fi for the control link
        let params = BeamTransportParameters.tcpInfraWiFi()
        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn
        self.status = .connecting(hostName: hostName, remote: remoteDesc)

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
                    self.stopLivenessWatch()
                    self.status = .failed(reason: err.localizedDescription)
                    self.connection?.cancel()
                    self.connection = nil
                }
            case .cancelled:
                BeamLog.warn("conn#\(idForLogs) cancelled (path=\(ps))", tag: "viewer")
                Task { @MainActor in
                    self.handshakeTimeoutTask?.cancel()
                    self.stopHeartbeats()
                    self.stopLivenessWatch()
                    if case .failed = self.status {
                        /* keep failed */
                    } else {
                        self.status = .idle
                    }
                }
            default:
                BeamLog.debug("conn#\(idForLogs) state=\(String(describing: state)) (path=\(ps))", tag: "viewer")
            }
        }

        // Extra diagnostics
        conn.viabilityUpdateHandler = { isViable in
            BeamLog.debug("conn#\(idForLogs) viable=\(isViable)", tag: "viewer")
        }
        conn.betterPathUpdateHandler = { hasBetter in
            BeamLog.debug("conn#\(idForLogs) betterPath=\(hasBetter)", tag: "viewer")
        }
        conn.pathUpdateHandler = { path in
            BeamLog.debug("conn#\(idForLogs) pathUpdate=\(pathSummary(path))", tag: "viewer")
        }

        conn.start(queue: .main)
    }

    @MainActor
    public func disconnect() {
        handshakeTimeoutTask?.cancel(); handshakeTimeoutTask = nil
        stopHeartbeats()
        stopLivenessWatch()
        connection?.cancel(); connection = nil
        rxBuffer.removeAll()
        status = .idle
        BeamLog.info("Disconnected", tag: "viewer")
    }

    // MARK: Handshake / IO

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

            handshakeTimeoutTask?.cancel()
            handshakeTimeoutTask = Task { [weak self] in
                // If your toolchain warns about nanoseconds:, swap to:
                // try? await Task.sleep(for: .seconds(8))
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
                    self.stopLivenessWatch()
                    if case .paired = self.status {
                        // keep paired label; UI will sort it out
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
        // 0) Broadcast status (M2)
        if let bs = try? JSONDecoder().decode(BroadcastStatus.self, from: line) {
            broadcastOn = bs.on
            BeamLog.info("Broadcast status → \(bs.on ? "ON" : "OFF")", tag: "viewer")
            return
        }

        // 1) Handshake response
        if let resp = try? JSONDecoder().decode(HandshakeResponse.self, from: line) {
            Task { @MainActor in
                self.handshakeTimeoutTask?.cancel()
                if resp.ok, let sid = resp.sessionID {
                    self.status = .paired(session: sid, udpPort: resp.udpPort)
                    BeamLog.info("Paired ✓ session=\(sid)", tag: "viewer")
                    self.lastRxAt = Date()
                    self.startHeartbeats()
                    self.startLivenessWatch()
                } else {
                    let reason = resp.message ?? "Rejected"
                    self.status = .failed(reason: reason)
                    BeamLog.warn("Pairing rejected: \(reason)", tag: "viewer")
                }
            }
            return
        }

        // 2) Media params (M3)
        if let mp = try? JSONDecoder().decode(MediaParams.self, from: line) {
            if case .paired(let sid, _) = status {
                status = .paired(session: sid, udpPort: mp.udpPort)
                BeamLog.info("Media params: udpPort=\(mp.udpPort)", tag: "viewer")
            }
            return
        }

        // 3) Heartbeat
        if (try? JSONDecoder().decode(Heartbeat.self, from: line)) != nil {
            lastRxAt = Date()
            BeamLog.debug("hb ✓", tag: "viewer")
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

    // MARK: Liveness diagnostics

    @MainActor
    private func startLivenessWatch() {
        stopLivenessWatch()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + livenessGrace, repeating: livenessGrace)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            guard case .paired = self.status else { return }
            let last = self.lastRxAt ?? Date()
            let gap = Date().timeIntervalSince(last)
            if gap > self.livenessGrace {
                BeamLog.warn("LIVENESS: no host traffic for \(Int(gap))s; marking failed (will close)", tag: "viewer")
                self.status = .failed(reason: "Lost contact with host")
                self.connection?.cancel()
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
