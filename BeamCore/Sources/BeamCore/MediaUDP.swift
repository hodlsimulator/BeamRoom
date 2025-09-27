//
//  MediaUDP.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  Host-side UDP listener + test-frame sender; now also publishes active peer to App Group (M4).
//

import Foundation
import Network
import OSLog

final class MediaUDP: @unchecked Sendable {
    private var listener: NWListener?
    private var activePeer: NWConnection?
    private var onPeerChanged: ((String?) -> Void)?
    private var peerDesc: String? { activePeer?.endpoint.debugDescription }

    // MARK: - Test stream
    private var streamTimer: DispatchSourceTimer?
    private var seq: UInt32 = 0
    // keep ≤ ~1200 bytes to avoid IP fragmentation
    private let w = 20, h = 12

    // Optional debug sampler
    private var bytesInWindow: Int = 0
    private var windowStart = Date()

    // Rate-limit “no peer” spam
    private var lastNoPeerLogAt: Date?

    // Breadcrumbs
    private var sawFirstHello = false
    private var sentFirstFrame = false
    private var streamBeganAt: Date?

    init(onPeerChanged: ((String?) -> Void)? = nil) {
        self.onPeerChanged = onPeerChanged
    }

    // MARK: - Lifecycle

    func start(onReady: @Sendable @escaping (UInt16) -> Void,
               onError: @Sendable @escaping (Error) -> Void)
    {
        do {
            let params = NWParameters.udp
            params.requiredInterfaceType = .wifi
            params.includePeerToPeer = false

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
                    BeamLog.error("Media UDP listener failed: \(err.localizedDescription)", tag: "host"); onError(err)
                case .setup:     BeamLog.debug("Media UDP state=setup", tag: "host")
                case .waiting(let e): BeamLog.warn("Media UDP waiting: \(e.localizedDescription)", tag: "host")
                case .cancelled: BeamLog.warn("Media UDP cancelled", tag: "host")
                @unknown default: BeamLog.debug("Media UDP state=\(String(describing: state))", tag: "host")
                }
            }
            lis.newConnectionHandler = { [weak self] conn in self?.installPeer(conn) }
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
        BeamConfig.setMediaPeer(host: nil, port: nil) // M4: clear
        BeamLog.info("Media UDP stopped", tag: "host")
    }

    // MARK: - Peer

    private func installPeer(_ conn: NWConnection) {
        // Replace any existing peer
        if let old = activePeer {
            BeamLog.warn("UDP peer replaced: \(old.endpoint.debugDescription) → \(conn.endpoint.debugDescription)", tag: "host")
            old.cancel()
        }
        activePeer = conn
        sawFirstHello = false
        sentFirstFrame = false

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                BeamLog.info("UDP peer ready: \(conn.endpoint.debugDescription)", tag: "host")
                self.onPeerChanged?(conn.endpoint.debugDescription)
                // Publish to App Group so the Upload extension can send directly (M4)
                if case let .hostPort(h, p) = (conn.endpoint) {
                    BeamConfig.setMediaPeer(host: h.debugDescription, port: p.rawValue)
                } else if let remote = conn.currentPath?.remoteEndpoint, case let .hostPort(h, p) = remote {
                    BeamConfig.setMediaPeer(host: h.debugDescription, port: p.rawValue)
                }
                self.receiveLoop(on: conn) // keep alive
            case .failed(let err):
                BeamLog.error("UDP peer failed: \(err.localizedDescription)", tag: "host")
                self.onPeerChanged?(nil)
                self.activePeer = nil
                BeamConfig.setMediaPeer(host: nil, port: nil)
            case .cancelled:
                BeamLog.warn("UDP peer cancelled", tag: "host")
                self.onPeerChanged?(nil)
                self.activePeer = nil
                BeamConfig.setMediaPeer(host: nil, port: nil)
            case .preparing: BeamLog.debug("UDP peer preparing", tag: "host")
            case .waiting(let e): BeamLog.warn("UDP peer waiting: \(e.localizedDescription)", tag: "host")
            @unknown default: BeamLog.debug("UDP peer state=\(String(describing: state))", tag: "host")
            }
        }
        conn.start(queue: .main)
    }

    private func receiveLoop(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, _ in
            if let self, let d = data, !d.isEmpty {
                if !self.sawFirstHello {
                    self.sawFirstHello = true
                    BeamLog.info("UDP ← first datagram \(d.count) bytes (hello/keepalive)", tag: "host")
                } else {
                    BeamLog.debug("UDP ← \(d.count) bytes (hello/keepalive)", tag: "host")
                }
            }
            self?.receiveLoop(on: conn)
        }
    }

    // MARK: - Test frames (unchanged)

    func startTestFrames() {
        stopTestFrames()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.1, repeating: 1.0 / 12.0) // ~12 fps
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        streamTimer = t
        seq = 0
        sentFirstFrame = false
        streamBeganAt = Date()
        lastNoPeerLogAt = nil
        BeamLog.info("Test stream START (fake frames)", tag: "host")
    }

    func stopTestFrames() {
        streamTimer?.cancel(); streamTimer = nil
        streamBeganAt = nil
        BeamLog.info("Test stream STOP", tag: "host")
    }

    private func tick() {
        guard let peer = activePeer else {
            let now = Date()
            if streamTimer != nil, (lastNoPeerLogAt == nil || now.timeIntervalSince(lastNoPeerLogAt!) >= 2.0) {
                lastNoPeerLogAt = now
                BeamLog.info("Test stream ticking but no active UDP peer yet; skipping send", tag: "host")
            }
            return
        }
        seq &+= 1
        let payload = makeGradientFrame(seq: seq, w: w, h: h)
        if !sentFirstFrame {
            sentFirstFrame = true
            BeamLog.info("UDP → first test frame \(w)x\(h) (\(payload.count) bytes) to \(peer.endpoint.debugDescription)", tag: "host")
        }
        bytesInWindow += payload.count
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 1.0 {
            let seconds = now.timeIntervalSince(windowStart)
            let kbps = Double(bytesInWindow * 8) / seconds / 1000.0
            BeamLog.debug(String(format: "UDP preview tx ~ %.1f kbps @ %dx%d", kbps, w, h), tag: "host")
            windowStart = now; bytesInWindow = 0
        }
        peer.send(content: payload, completion: .contentProcessed { maybeErr in
            if let e = maybeErr { BeamLog.error("UDP send error: \(e.localizedDescription)", tag: "host") }
        })
    }

    /// Wire: [u32 'BMRM'][u32 seq][u16 w][u16 h] + BGRA32
    private func makeGradientFrame(seq: UInt32, w: Int, h: Int) -> Data {
        var out = Data(capacity: 12 + w * h * 4)
        out.appendBE(UInt32(0x424D524D)) // 'BMRM'
        out.appendBE(seq)
        out.appendBE(UInt16(w))
        out.appendBE(UInt16(h))
        let t = Double(seq) * 0.08
        let maxX = max(1, w - 1)
        let maxY = max(1, h - 1)
        for y in 0..<h {
            for x in 0..<w {
                let fx = Double(x) / Double(maxX)
                let fy = Double(y) / Double(maxY)
                let r = UInt8( 255 * max(0.0, min(1.0, sin(t + fx * .pi) * 0.5 + 0.5)) )
                let g = UInt8( 255 * max(0.0, min(1.0, sin(t + fy * .pi * 0.8) * 0.5 + 0.5)) )
                let b = UInt8( 255 * max(0.0, min(1.0, sin(t + (fx+fy) * .pi * 0.6) * 0.5 + 0.5)) )
                out.append(contentsOf: [0xFF, b, g, r]) // BGRA little
            }
        }
        return out
    }
}

private extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { raw in
            guard let base = raw.baseAddress else { return }
            self.append(base.bindMemory(to: UInt8.self, capacity: raw.count), count: raw.count)
        }
    }
}
