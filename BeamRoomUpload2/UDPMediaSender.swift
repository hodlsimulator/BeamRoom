//
//  UDPMediaSender.swift
//  BeamRoomUpload2
//
//  Created by . . on 10/31/25.
//
//  Broadcast Upload extension → owns the UDP media port and sends AVCC H.264
//  directly to the active Viewer peer. Viewers send periodic "BRHI!" keep-alives
//  to maintain the active mapping.
//

import Foundation
import Network
import OSLog
import BeamCore

actor UDPMediaSender {

    // MARK: - Singleton

    static let shared = UDPMediaSender()

    // MARK: - State

    private let log = Logger(subsystem: BeamConfig.subsystemExt, category: "udp-send")
    private let queue = DispatchQueue(label: "beamroom.mediaudp.ext")

    private var listener: NWListener?
    private var conns: [String: NWConnection] = [:] // "ip:port"

    private var activeKey: String?
    private var activeLastSeen: Date = .distantPast
    private var expireTimer: DispatchSourceTimer?

    private var localPort: UInt16 = 0
    private var seq: UInt32 = 0

    /// Conservative payload to avoid IP fragmentation on Wi-Fi.
    private let maxUDPPayload = 1200

    /// Fixed H264Wire header size (big-endian encoding).
    private let fixedHeaderBytes = 20

    // MARK: - Lifecycle

    func start() async {
        await startListenerIfNeeded(reason: "start")
    }

    func stop() async {
        await stopInternal()
    }

    // MARK: - Public API

    func sendAVCC(
        width: Int,
        height: Int,
        avcc: Data,
        paramSets: H264Wire.ParamSets?,
        isKeyframe: Bool
    ) async {
        guard let (key, c) = currentSendConnection() else { return }

        var cfg = Data()
        var flags = H264Wire.Flags()

        if isKeyframe {
            flags.insert(.keyframe)
        }

        if isKeyframe, let ps = paramSets {
            cfg = H264Wire.encodeParamSets(ps)
            if !cfg.isEmpty {
                flags.insert(.hasParamSet)
            }
        }

        let max0 = maxUDPPayload - fixedHeaderBytes - (cfg.isEmpty ? 0 : cfg.count)
        let chunk0 = max(0, min(max0, avcc.count))
        let remaining = avcc.count - chunk0
        let perPart = maxUDPPayload - fixedHeaderBytes
        let extraParts = (remaining > 0) ? Int(ceil(Double(remaining) / Double(perPart))) : 0
        let partCount = 1 + extraParts

        do {
            let h0 = H264Wire.Header(
                seq: seq,
                partIndex: 0,
                partCount: UInt16(partCount),
                flags: flags,
                width: UInt16(max(0, min(width, Int(UInt16.max)))),
                height: UInt16(max(0, min(height, Int(UInt16.max)))),
                configBytes: UInt16(cfg.count)
            )

            var pkt0 = encodeHeaderBE(h0)
            if !cfg.isEmpty { pkt0.append(cfg) }
            if chunk0 > 0 { pkt0.append(avcc.prefix(chunk0)) }

            try await sendPacket(pkt0, on: c)
        } catch {
            log.error("send part0 failed: \(error.localizedDescription, privacy: .public)")
            evict(key)
            return
        }

        var sent = chunk0
        var idx: UInt16 = 1

        while sent < avcc.count {
            let n = min(perPart, avcc.count - sent)

            let hi = H264Wire.Header(
                seq: seq,
                partIndex: idx,
                partCount: UInt16(partCount),
                flags: flags,
                width: UInt16(max(0, min(width, Int(UInt16.max)))),
                height: UInt16(max(0, min(height, Int(UInt16.max)))),
                configBytes: 0
            )

            var pkt = encodeHeaderBE(hi)
            pkt.append(avcc.subdata(in: sent ..< (sent + n)))

            do {
                try await sendPacket(pkt, on: c)
            } catch {
                log.error("send part \(idx) failed: \(error.localizedDescription, privacy: .public)")
                evict(key)
                return
            }

            sent += n
            idx &+= 1
        }

        // Outbound success counts as activity. Updating only after success avoids
        // pinning a dead activeKey forever.
        activeKey = key
        activeLastSeen = Date()

        seq &+= 1
    }

    // MARK: - Listener / peer management

    private func startListenerIfNeeded(reason: String) async {
        guard listener == nil else { return }

        let params = NWParameters.udp
        params.includePeerToPeer = true
        params.prohibitedInterfaceTypes = [.cellular]

        // Prefer a stable port so if the extension is restarted/killed and comes back,
        // the Viewer can keep using the same UDP destination without needing a control update.
        let preferredPort = NWEndpoint.Port(rawValue: BeamConfig.controlPort &+ 1)

        do {
            let lis: NWListener

            if let p = preferredPort {
                do {
                    lis = try NWListener(using: params, on: p)
                    log.notice("Media UDP listener starting on preferred port \(p.rawValue) (\(reason, privacy: .public))")
                } catch {
                    log.error("Preferred UDP port \(p.rawValue) unavailable: \(error.localizedDescription, privacy: .public) — falling back to ephemeral port")
                    lis = try NWListener(using: params, on: .any)
                    log.notice("Media UDP listener starting on ephemeral port (\(reason, privacy: .public))")
                }
            } else {
                lis = try NWListener(using: params, on: .any)
                log.notice("Media UDP listener starting on ephemeral port (\(reason, privacy: .public))")
            }

            listener = lis

            lis.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task { await self.handleListenerState(state, listener: lis) }
            }

            lis.newConnectionHandler = { [weak self] nw in
                guard let self else { return }
                Task { await self.handleNewConnection(nw) }
            }

            lis.start(queue: queue)
        } catch {
            log.error("Media UDP listener start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleListenerState(_ state: NWListener.State, listener lis: NWListener) async {
        switch state {
        case .ready:
            let port = lis.port?.rawValue ?? 0
            localPort = UInt16(port)
            BeamConfig.setBroadcastUDPPort(localPort)
            log.notice("Media UDP ready on port \(port)")

        case .failed(let err):
            log.error("Media UDP failed: \(err.localizedDescription, privacy: .public)")
            await stopInternal()

        case .cancelled:
            break

        default:
            break
        }
    }

    private func handleNewConnection(_ nw: NWConnection) async {
        let key = Self.describeRemote(nw)
        conns[key] = nw

        nw.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleConnState(state, key: key, conn: nw) }
        }

        nw.start(queue: queue)
    }

    private func handleConnState(_ state: NWConnection.State, key: String, conn: NWConnection) async {
        switch state {
        case .ready:
            BeamLog.info("UDP peer ready: \(key)", tag: "ext")
            adoptActivePeer(key)
            startReceiveLoop(on: conn, key: key)

        case .failed(let err):
            BeamLog.error("UDP peer failed: \(err.localizedDescription)", tag: "ext")
            evict(key)

        case .cancelled:
            BeamLog.warn("UDP peer cancelled: \(key)", tag: "ext")
            evict(key)

        default:
            break
        }
    }

    private func startReceiveLoop(on conn: NWConnection, key: String) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            Task { await self.handleReceive(data: data, error: error, key: key, conn: conn) }
        }
    }

    private func handleReceive(data: Data?, error: NWError?, key: String, conn: NWConnection) async {
        if let error {
            BeamLog.error("UDP recv error: \(error.localizedDescription)", tag: "ext")
            evict(key)
            return
        }

        if let d = data, !d.isEmpty {
            adoptActivePeer(key, sawBytes: d.count)
        }

        if conns[key] != nil {
            startReceiveLoop(on: conn, key: key)
        }
    }

    private func adoptActivePeer(_ key: String, sawBytes: Int? = nil) {
        let previous = activeKey
        activeKey = key
        activeLastSeen = Date()

        if previous != key {
            if let previous {
                BeamLog.warn("UDP peer replaced: \(previous) → \(key)", tag: "ext")
            }
            startExpiryTimerIfNeeded()
        }

        if let count = sawBytes {
            if count == 5 {
                BeamLog.info("UDP ← hello/keepalive (5 bytes)", tag: "ext")
            } else {
                BeamLog.info("UDP ← \(count) bytes", tag: "ext")
            }
        }
    }

    private func startExpiryTimerIfNeeded() {
        guard expireTimer == nil else { return }

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1.0, repeating: 1.0)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.expireCheck() }
        }
        t.resume()
        expireTimer = t
    }

    private func expireCheck(ttl: TimeInterval = 20.0) async {
        if let _ = activeKey, Date().timeIntervalSince(activeLastSeen) > ttl {
            BeamLog.warn("UDP peer expired (no datagrams in \(Int(ttl))s)", tag: "ext")
            activeKey = nil
        }
    }

    private func evict(_ key: String) {
        conns[key]?.cancel()
        conns.removeValue(forKey: key)
        if key == activeKey {
            activeKey = nil
        }
    }

    private func stopInternal() async {
        expireTimer?.cancel()
        expireTimer = nil

        for (_, c) in conns {
            c.cancel()
        }
        conns.removeAll()

        listener?.cancel()
        listener = nil

        activeKey = nil
        activeLastSeen = .distantPast
        localPort = 0
        seq = 0

        BeamConfig.setBroadcastUDPPort(nil)
    }

    // MARK: - Sending

    private func currentSendConnection() -> (String, NWConnection)? {
        if let key = activeKey, let c = conns[key] {
            return (key, c)
        }

        if conns.count == 1, let (onlyKey, onlyConn) = conns.first {
            activeKey = onlyKey
            startExpiryTimerIfNeeded()
            return (onlyKey, onlyConn)
        }

        return nil
    }

    private func sendPacket(_ data: Data, on conn: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let e = error {
                    cont.resume(throwing: e)
                } else {
                    cont.resume(returning: ())
                }
            })
        }
    }

    // MARK: - Header encode helper

    private func encodeHeaderBE(_ h: H264Wire.Header) -> Data {
        var out = Data(capacity: fixedHeaderBytes)
        out.appendBE(H264Wire.magic)
        out.appendBE(h.seq)
        out.appendBE(h.partIndex)
        out.appendBE(h.partCount)
        out.appendBE(h.flags.rawValue)
        out.appendBE(h.width)
        out.appendBE(h.height)
        out.appendBE(h.configBytes)
        return out
    }

    // MARK: - Remote endpoint formatting

    private static func describeRemote(_ nw: NWConnection) -> String {
        if case let .hostPort(host, port) = nw.endpoint {
            return "\(host.debugDescription):\(port.rawValue)"
        }
        if let ep = nw.currentPath?.remoteEndpoint, case let .hostPort(host, port) = ep {
            return "\(host.debugDescription):\(port.rawValue)"
        }
        return "?:0"
    }
}
