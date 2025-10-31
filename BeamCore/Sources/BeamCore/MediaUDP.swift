//
//  MediaUDP.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  Host-side UDP listener + (optional) M3 fake-frame sender.
//  Also bridges the active Viewer peer (ip:port) into the App Group so the
//  Broadcast Upload extension can stream H.264 to the Host, which then forwards
//  to the active Viewer. Viewer keep-alives (BRHI!) maintain the mapping.
//

import Foundation
import Network
import OSLog

public final class MediaUDP: @unchecked Sendable {

    public typealias ReadyHandler = @Sendable (_ udpPort: UInt16) -> Void
    public typealias ErrorHandler = @Sendable (_ error: Error) -> Void
    public typealias PeerChangedHandler = @Sendable (_ peer: String?) -> Void

    public init(onPeerChanged: PeerChangedHandler? = nil) {
        self.onPeerChanged = onPeerChanged
    }

    public func start(onReady: @escaping ReadyHandler, onError: @escaping ErrorHandler) {
        guard listener == nil else { return }

        mediaOS.notice("Media UDP starting…")

        // IMPORTANT: do not restrict to .wifi — must accept 127.0.0.1 from the Upload extension.
        let params = NWParameters.udp
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
                    BeamConfig.setBroadcastUDPPort(UInt16(port))
                    onReady(UInt16(port))
                case .failed(let error):
                    self.stop()
                    BeamLog.error("Media UDP failed: \(error.localizedDescription)", tag: "host")
                    onError(error)
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
        listener?.cancel(); listener = nil

        activeKey = nil
        activeLastSeen = .distantPast
        publishActivePeer(nil)

        expireTimer?.cancel(); expireTimer = nil

        BeamLog.info("Media UDP stopped", tag: "host")
    }

    public func startTestFrames(fps: Double = 12.0, width: Int = 20, height: Int = 12) {
        guard testTimer == nil else { return }
        m3W = width; m3H = height; m3Seq = 0

        let t = DispatchSource.makeTimerSource(queue: queue)
        let interval = DispatchTimeInterval.milliseconds(Int(1000.0 / max(1.0, fps)))
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.tickTestFrame() }
        t.resume()
        testTimer = t

        BeamLog.info("Test stream START", tag: "host")
    }

    public func stopTestFrames() {
        testTimer?.cancel(); testTimer = nil
        BeamLog.info("Test stream STOP", tag: "host")
    }

    private let queue = DispatchQueue(label: "media-udp.host")
    private var listener: NWListener?
    private var conns: [String: NWConnection] = [:] // "ip:port"

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

        let isUplink = Self.isLoopbackKey(key) // extension → host (127.0.0.1)

        nw.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            guard let self else { return }
            switch state {
            case .ready:
                if isUplink {
                    BeamLog.info("UDP uplink ready (local): \(key)", tag: "host")
                } else {
                    BeamLog.info("UDP peer ready: \(key)", tag: "host")
                    self.adoptActivePeer(key)
                }
                self.startReceiveLoop(on: nw, key: key, isUplink: isUplink)
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

    private func startReceiveLoop(on nw: NWConnection, key: String, isUplink: Bool) {
        nw.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                BeamLog.error("UDP recv error: \(error.localizedDescription)", tag: "host")
                self.evict(key)
                return
            }

            if let d = data, !d.isEmpty {
                if isUplink {
                    if H264Wire.parseHeaderBE(d) != nil {
                        self.forwardToActivePeer(d)
                    }
                } else {
                    self.adoptActivePeer(key, sawBytes: d.count)
                }
            }

            if self.conns[key] != nil {
                self.startReceiveLoop(on: nw, key: key, isUplink: isUplink)
            }
        }
    }

    private func forwardToActivePeer(_ data: Data) {
        guard let c = connForActivePeer() else { return }
        c.send(content: data, completion: .contentProcessed { _ in })
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

    private func tickTestFrame() {
        guard let c = connForActivePeer() else {
            BeamLog.info("Test stream ticking but no active UDP peer yet; skipping send", tag: "host")
            return
        }

        var data = Data()
        data.reserveCapacity(12 + m3W * m3H * 4)

        var magic: UInt32 = 0x424D524D
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
                let v = UInt8((x + y + t) % 255)
                data.append(v)        // B
                data.append(255 - v)  // G
                data.append(v)        // R
                data.append(255)      // A
            }
        }

        c.send(content: data, completion: .contentProcessed { _ in })
    }

    private func publishActivePeer(_ key: String?) {
        if let key, let (host, port) = Self.split(key) {
            BeamConfig.setMediaPeer(host: host, port: port)
        } else {
            BeamConfig.setMediaPeer(host: nil, port: nil)
        }
    }

    private static func describeRemote(_ nw: NWConnection) -> String {
        if case let .hostPort(host, port) = nw.endpoint {
            return "\(host.debugDescription):\(port.rawValue)"
        }
        if let ep = nw.currentPath?.remoteEndpoint, case let .hostPort(host, port) = ep {
            return "\(host.debugDescription):\(port.rawValue)"
        }
        return "?:0"
    }

    private static func isLoopbackKey(_ key: String) -> Bool {
        guard let (host, _) = split(key) else { return false }
        return host == "127.0.0.1" || host == "::1" || host == "localhost"
    }

    private static func split(_ key: String) -> (String, UInt16)? {
        if key.hasPrefix("[") {
            guard
                let close = key.firstIndex(of: "]"),
                let colon = key[key.index(after: close)...].lastIndex(of: ":")
            else { return nil }
            let host = String(key[key.index(after: key.startIndex)..<close])
            let portStr = String(key[key.index(after: colon)...])
            guard let p = UInt16(portStr) else { return nil }
            return (host, p)
        } else {
            guard let colon = key.lastIndex(of: ":") else { return nil }
            let host = String(key[..<colon])
            let portStr = String(key[key.index(after: colon)...])
            guard let p = UInt16(portStr) else { return nil }
            return (host, p)
        }
    }
}
