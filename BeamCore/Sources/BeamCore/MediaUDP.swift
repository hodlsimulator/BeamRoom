//
//  MediaUDP.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  Host-side UDP listener + (optional) M3 fake-frame sender.
//  Also bridges the currently active Viewer peer (ip:port) into the App Group
//  so the Broadcast Upload extension can stream real H.264 to the same peer.
//
//  Works with UDPMediaClient.swift (Viewer) which already sends BRHI!    keep-alives.
//  After this change, every inbound datagram refreshes the active peer and makes
//  fake frames resume immediately after reconnects. When Broadcast is ON, you
//  typically won’t use fake frames at all.
//

import Foundation
import Network
import OSLog

public final class MediaUDP {

    // MARK: - Public types (make closures Sendable)
    public typealias ReadyHandler = @Sendable (_ udpPort: UInt16) -> Void
    public typealias ErrorHandler = @Sendable (_ error: Error) -> Void
    public typealias PeerChangedHandler = @Sendable (_ peer: String?) -> Void

    // MARK: - Init
    public init(onPeerChanged: PeerChangedHandler? = nil) {
        self.onPeerChanged = onPeerChanged
    }

    // MARK: - API
    public func start(onReady: @escaping ReadyHandler, onError: @escaping ErrorHandler) {
        guard listener == nil else { return }
        mediaOS.notice("Media UDP starting…")

        let params = NWParameters.udp
        params.requiredInterfaceType = .wifi
        params.includePeerToPeer = false

        do {
            let lis = try NWListener(using: params, on: .any) // ephemeral
            listener = lis

            lis.stateUpdateHandler = { [weak self] (state: NWListener.State) in
                guard let self else { return }
                switch state {
                case .ready:
                    let port = lis.port?.rawValue ?? 0
                    self.localPort = UInt16(port)
                    BeamLog.info("Media UDP listener ready on \(port)", tag: "host")
                    self.mediaOS.notice("Media UDP ready on port \(port)")
                    // Tell the rest of the app (Host UI + control server)
                    BeamConfig.setBroadcastUDPPort(UInt16(port))
                    onReady(UInt16(port))
                case .failed(let error):
                    self.stop()
                    BeamLog.error("Media UDP failed: \(error.localizedDescription)", tag: "host")
                    onError(error)
                case .cancelled:
                    break
                default:
                    break
                }
            }

            lis.newConnectionHandler = { [weak self] (nw: NWConnection) in
                self?.handleNewConnection(nw)
            }

            lis.start(queue: queue)
        } catch {
            onError(error)
        }
    }

    public func stop() {
        stopTestFrames()

        for (_, c) in conns { c.cancel() }
        conns.removeAll()

        listener?.cancel()
        listener = nil

        activeKey = nil
        activeLastSeen = .distantPast
        publishActivePeer(nil)

        expireTimer?.cancel(); expireTimer = nil

        BeamLog.info("Media UDP stopped", tag: "host")
    }

    // MARK: - Fake preview (M3) — optional
    public func startTestFrames(fps: Double = 12.0, width: Int = 20, height: Int = 12) {
        guard testTimer == nil else { return }
        m3W = width
        m3H = height
        m3Seq = 0

        let t = DispatchSource.makeTimerSource(queue: queue)
        let interval = DispatchTimeInterval.milliseconds(Int(1000.0 / max(1.0, fps)))
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            self?.tickTestFrame()
        }
        t.resume()
        testTimer = t

        BeamLog.info("Test stream START", tag: "host")
    }

    public func stopTestFrames() {
        testTimer?.cancel(); testTimer = nil
        BeamLog.info("Test stream STOP", tag: "host")
    }

    // MARK: - Internals
    private let queue = DispatchQueue(label: "media-udp.host")
    private var listener: NWListener?
    private var conns: [String: NWConnection] = [:] // key = "ip:port"

    private var activeKey: String? = nil
    private var activeLastSeen: Date = .distantPast
    private var expireTimer: DispatchSourceTimer?

    private var testTimer: DispatchSourceTimer?
    private var m3Seq: UInt32 = 0
    private var m3W: Int = 20
    private var m3H: Int = 12

    private var localPort: UInt16 = 0

    private let onPeerChanged: PeerChangedHandler?
    private let mediaOS = Logger(subsystem: BeamConfig.subsystemHost, category: "udp-media")

    private func handleNewConnection(_ nw: NWConnection) {
        let key = Self.describeRemote(nw)
        conns[key] = nw

        nw.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            guard let self else { return }
            switch state {
            case .ready:
                BeamLog.info("UDP peer ready: \(key)", tag: "host")
                self.adoptActivePeer(key)
                self.startReceiveLoop(on: nw, key: key)
            case .failed(let error):
                BeamLog.error("UDP peer failed: \(error.localizedDescription)", tag: "host")
                self.evict(key)
            case .cancelled:
                BeamLog.warn("UDP peer cancelled", tag: "host")
                self.evict(key)
            default:
                break
            }
        }

        nw.start(queue: queue)
    }

    private func startReceiveLoop(on nw: NWConnection, key: String) {
        nw.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                BeamLog.error("UDP recv error: \(error.localizedDescription)", tag: "host")
                self.evict(key)
                return
            }

            if let d = data, !d.isEmpty {
                self.adoptActivePeer(key, sawBytes: d.count)
            }

            if self.conns[key] != nil {
                self.startReceiveLoop(on: nw, key: key)
            }
        }
    }

    private func adoptActivePeer(_ key: String, sawBytes: Int? = nil) {
        let was = activeKey
        activeKey = key
        activeLastSeen = Date()

        if was != key {
            if let was { BeamLog.warn("UDP peer replaced: \(was) → \(key)", tag: "host") }
            publishActivePeer(key)
            onPeerChanged?(key)
            startExpiryTimerIfNeeded()
        }

        if let count = sawBytes {
            if count == 5 {
                BeamLog.info("UDP ← first datagram 5 bytes (hello/keepalive)", tag: "host")
            } else {
                BeamLog.info("UDP ← first datagram \(count) bytes", tag: "host")
            }
        }
    }

    private func startExpiryTimerIfNeeded() {
        guard expireTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1.0, repeating: 1.0)
        t.setEventHandler { [weak self] in self?.expireCheck() }
        t.resume()
        expireTimer = t
    }

    private func expireCheck(ttl: TimeInterval = 6.0) {
        guard let key = activeKey else { return }
        if Date().timeIntervalSince(activeLastSeen) > ttl {
            BeamLog.warn("UDP peer expired (no datagrams in \(Int(ttl))s)", tag: "host")
            activeKey = nil
            publishActivePeer(nil)
            onPeerChanged?(nil)
        }
    }

    private func evict(_ key: String) {
        conns[key]?.cancel()
        conns.removeValue(forKey: key)
        if key == activeKey {
            activeKey = nil
            publishActivePeer(nil)
            onPeerChanged?(nil)
        }
    }

    private func connForActivePeer() -> NWConnection? {
        guard let key = activeKey else { return nil }
        return conns[key]
    }

    // MARK: - Test frame tick (M3)
    private func tickTestFrame() {
        guard let c = connForActivePeer() else {
            BeamLog.info("Test stream ticking but no active UDP peer yet; skipping send", tag: "host")
            return
        }

        var data = Data()
        data.reserveCapacity(12 + m3W * m3H * 4)

        var magic: UInt32 = 0x424D524D // 'BMRM'
        data.append(contentsOf: withUnsafeBytes(of: magic.bigEndian, Array.init))

        m3Seq &+= 1
        var seqBE = m3Seq.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: seqBE, Array.init))

        var wBE = UInt16(m3W).bigEndian
        var hBE = UInt16(m3H).bigEndian
        data.append(contentsOf: withUnsafeBytes(of: wBE, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: hBE, Array.init))

        let t = Int((Date().timeIntervalSinceReferenceDate * 60).truncatingRemainder(dividingBy: 255))
        for y in 0..<m3H {
            for x in 0..<m3W {
                let b = UInt8((x * 7 + t) & 0xFF)
                let g = UInt8((y * 11 + t * 2) & 0xFF)
                let r = UInt8(((x + y) * 5 + t * 3) & 0xFF)
                data.append(b); data.append(g); data.append(r); data.append(0xFF)
            }
        }

        c.send(content: data, completion: .contentProcessed { err in
            if let err { BeamLog.error("UDP send error: \(err.localizedDescription)", tag: "host") }
        })
    }

    // MARK: - Active peer bridge (App Group)
    private func publishActivePeer(_ key: String?) {
        if let key, let (host, port) = Self.split(key) {
            BeamConfig.setMediaPeer(host: host, port: port)
        } else {
            BeamConfig.setMediaPeer(host: nil, port: nil)
        }
    }

    // MARK: - Utilities
    private static func describeRemote(_ nw: NWConnection) -> String {
        // Prefer the endpoint
        if case let .hostPort(host, port) = nw.endpoint {
            return "\(host.debugDescription):\(port.rawValue)"
        }
        // Fallback: current path's remote endpoint
        if let ep = nw.currentPath?.remoteEndpoint, case let .hostPort(host, port) = ep {
            return "\(host.debugDescription):\(port.rawValue)"
        }
        return "?:0"
    }

    private static func split(_ key: String) -> (String, UInt16)? {
        if key.hasPrefix("[") {
            guard let close = key.firstIndex(of: "]"),
                  let colon = key[key.index(after: close)...].lastIndex(of: ":") else { return nil }
            let host = String(key[key.index(after: key.startIndex)..<close])
            let portStr = String(key[key.index(after: colon)...])
            guard let port = UInt16(portStr) else { return nil }
            return (host, port)
        } else {
            guard let colon = key.lastIndex(of: ":") else { return nil }
            let host = String(key[..<colon])
            let portStr = String(key[key.index(after: colon)...])
            guard let port = UInt16(portStr) else { return nil }
            return (host, port)
        }
    }
}

extension MediaUDP: @unchecked Sendable {}
