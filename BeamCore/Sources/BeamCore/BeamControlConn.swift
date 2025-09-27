//
//  BeamControlConn.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  Per-connection wrapper for the host’s TCP control plane.
//

import Foundation
import Network
import OSLog

@MainActor
final class Conn {
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
                default:
                    break
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

    // MARK: RX

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
                server?.queuePending(for: self, code: req.code) // Viewer has a timeout; no immediate reply here.
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

    // MARK: TX helpers

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

    private func send<T: Codable>(_ payload: T, note: String) {
        do {
            let bytes = try Frame.encodeLine(payload)
            nw.send(content: bytes, completion: .contentProcessed { _ in
                /* small & frequent; skip log */
            })
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
        hbTimer?.cancel(); hbTimer = nil
    }
}
