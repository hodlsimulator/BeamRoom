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
                    if let p = self?.listener?.port?.rawValue { onReady(p) }
                case .failed(let err):
                    onError(err)
                default:
                    break
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
                self.receiveLoop(on: conn) // keep alive
            case .failed(let err):
                BeamLog.error("UDP peer failed: \(err.localizedDescription)", tag: "host")
                self.onPeerChanged?(nil)
                self.activePeer = nil   // clear stale peer to avoid sends on dead socket
            case .cancelled:
                BeamLog.warn("UDP peer cancelled", tag: "host")
                self.onPeerChanged?(nil)
                self.activePeer = nil   // clear on cancel too
            default:
                break
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

        // Optional: DEBUG summary once per second; no per-frame spam.
        bytesInWindow += payload.count
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 1.0 {
            let seconds = now.timeIntervalSince(windowStart)
            let kbps = Double(bytesInWindow * 8) / seconds / 1000.0
            BeamLog.debug(String(format: "UDP preview ~ %.1f kbps @ %dx%d", kbps, w, h), tag: "host")
            windowStart = now
            bytesInWindow = 0
        }

        peer.send(content: payload, completion: .contentProcessed { _ in
            // quiet
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
                let fx = Double(x) / Double(w)
                let fy = Double(y) / Double(h)
                let r = UInt8( (sin(t + fx * 6.28318) * 0.5 + 0.5) * 255.0 )
                let g = UInt8( (sin(t + fy * 6.28318) * 0.5 + 0.5) * 255.0 )
                let b = UInt8( (sin(t + (fx + fy) * 3.14159) * 0.5 + 0.5) * 255.0 )
                out.append(contentsOf: [b, g, r, 0xFF]) // BGRA
            }
        }
        return out
    }
}
