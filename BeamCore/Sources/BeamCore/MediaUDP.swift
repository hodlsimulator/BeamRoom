//
//  MediaUDP.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  Host-side UDP listener + tiny fake-frame sender used by the M3 preview.
//

import Foundation
import Network
import OSLog

/// We keep MediaUDP on the main queue only; mark as @unchecked Sendable to appease @Sendable closures.
final class MediaUDP: @unchecked Sendable {

    private var listener: NWListener?
    private var activePeer: NWConnection?
    private var onPeerChanged: ((String?) -> Void)?

    private var peerDesc: String? { activePeer?.endpoint.debugDescription }

    // Test stream
    private var streamTimer: DispatchSourceTimer?
    private var seq: UInt32 = 0

    // IMPORTANT: keep one datagram per frame under ~65 KB:
    // 160 × 90 × 4 + 12 header = 57,612 bytes (safe).
    private let w = 160, h = 90

    // Optional debug sampler (summarise throughput)
    private var bytesInWindow: Int = 0
    private var windowStart = Date()

    // Rate-limit “no peer” spam
    private var lastNoPeerLogAt: Date?

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

            // Use port-less init; system assigns ephemeral port.
            let lis = try NWListener(using: params)
            listener = lis

            lis.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let p = self?.listener?.port?.rawValue {
                        BeamLog.info("Media UDP listener ready on \(p)", tag: "host")
                        onReady(p)
                    } else {
                        BeamLog.warn("Media UDP ready but missing port", tag: "host")
                    }
                case .failed(let err):
                    BeamLog.error("Media UDP listener failed: \(err.localizedDescription)", tag: "host")
                    onError(err)
                case .setup:
                    BeamLog.debug("Media UDP state=setup", tag: "host")
                case .waiting(let e):
                    BeamLog.warn("Media UDP waiting: \(e.localizedDescription)", tag: "host")
                case .cancelled:
                    BeamLog.warn("Media UDP cancelled", tag: "host")
                @unknown default:
                    BeamLog.debug("Media UDP state=\(String(describing: state))", tag: "host")
                }
            }

            // Incoming UDP “connections” represent remote addresses that send us a datagram.
            lis.newConnectionHandler = { [weak self] conn in
                self?.installPeer(conn)
            }

            lis.start(queue: .main)
            BeamLog.info("Media UDP starting…", tag: "host")
        } catch {
            BeamLog.error("Media UDP start error: \(error.localizedDescription)", tag: "host")
            onError(error)
        }
    }

    func stop() {
        stopTestFrames()
        if let old = activePeer {
            BeamLog.warn("UDP peer closing: \(old.endpoint.debugDescription)", tag: "host")
        }
        activePeer?.cancel(); activePeer = nil
        listener?.cancel(); listener = nil
        onPeerChanged?(nil)
        BeamLog.info("Media UDP stopped", tag: "host")
    }

    // MARK: Peer

    private func installPeer(_ conn: NWConnection) {
        // Replace any existing peer
        if let old = activePeer {
            BeamLog.warn("UDP peer replaced: \(old.endpoint.debugDescription) → \(conn.endpoint.debugDescription)", tag: "host")
            old.cancel()
        }
        activePeer = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                BeamLog.info("UDP peer ready: \(conn.endpoint.debugDescription)", tag: "host")
                self.onPeerChanged?(conn.endpoint.debugDescription)
                self.receiveLoop(on: conn) // keep alive
            case .failed(let err):
                BeamLog.error("UDP peer failed: \(err.localizedDescription)", tag: "host")
                self.onPeerChanged?(nil)
                self.activePeer = nil // clear stale peer to avoid sends on dead socket
            case .cancelled:
                BeamLog.warn("UDP peer cancelled", tag: "host")
                self.onPeerChanged?(nil)
                self.activePeer = nil // clear on cancel too
            case .preparing:
                BeamLog.debug("UDP peer preparing", tag: "host")
            case .waiting(let e):
                BeamLog.warn("UDP peer waiting: \(e.localizedDescription)", tag: "host")
            @unknown default:
                BeamLog.debug("UDP peer state=\(String(describing: state))", tag: "host")
            }
        }

        conn.start(queue: .main)
    }

    private func receiveLoop(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, _ in
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
        BeamLog.info("Test stream START (fake frames)", tag: "host")
    }

    func stopTestFrames() {
        streamTimer?.cancel()
        streamTimer = nil
        BeamLog.info("Test stream STOP", tag: "host")
    }

    private func tick() {
        guard let peer = activePeer else {
            let now = Date()
            if lastNoPeerLogAt == nil || now.timeIntervalSince(lastNoPeerLogAt!) >= 2.0 {
                lastNoPeerLogAt = now
                BeamLog.debug("Test stream tick: no active peer; skipping send", tag: "host")
            }
            return
        }

        seq &+= 1
        let payload = makeGradientFrame(seq: seq, w: w, h: h)

        // Optional: DEBUG summary once per second; no per-frame spam.
        bytesInWindow += payload.count
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 1.0 {
            let seconds = now.timeIntervalSince(windowStart)
            let kbps = Double(bytesInWindow * 8) / seconds / 1000.0
            BeamLog.debug(String(format: "UDP preview tx ~ %.1f kbps @ %dx%d", kbps, w, h), tag: "host")
            windowStart = now
            bytesInWindow = 0
        }

        peer.send(content: payload, completion: .contentProcessed { maybeErr in
            if let e = maybeErr {
                BeamLog.error("UDP send error: \(e.localizedDescription)", tag: "host")
            }
        })
    }

    private func makeGradientFrame(seq: UInt32, w: Int, h: Int) -> Data {
        var out = Data(capacity: 12 + w*h*4)

        // Header: [u32 magic 'BMRM'][u32 seq][u16 w][u16 h] (big-endian)
        out.appendBE(UInt32(0x424D524D)) // 'BMRM'
        out.appendBE(seq)
        out.appendBE(UInt16(w))
        out.appendBE(UInt16(h))

        // Pixels (BGRA32): simple moving gradient
        out.reserveCapacity(12 + w*h*4)
        let t = Double(seq) * 0.08
        for y in 0..<h {
            for x in 0..<w {
                let fx = Double(x) / Double(max(1, w - 1))
                let fy = Double(y) / Double(max(1, h - 1))
                let r = UInt8((sin(fx * 6.283 + t) * 0.5 + 0.5) * 255)
                let g = UInt8((sin(fy * 6.283 + t * 0.8) * 0.5 + 0.5) * 255)
                let b = UInt8((sin((fx + fy) * 3.1415 + t * 0.6) * 0.5 + 0.5) * 255)
                out.append(b) // BGRA
                out.append(g)
                out.append(r)
                out.append(0xFF) // A
            }
        }
        return out
    }
}
