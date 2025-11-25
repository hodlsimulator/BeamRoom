//
//  UDPMediaSender.swift
//  BeamRoomHost
//
//  Created by . . on 10/31/25.
//
//  Broadcast Upload extension → sends AVCC H.264 over UDP.
//  - Initially targets the Host’s local media listener (127.0.0.1:port).
//  - Once the Host discovers an active Viewer peer and publishes it via
//    BeamConfig.setMediaPeer(host:port:), the extension reconnects and
//    streams directly to the Viewer’s IP:port over Wi‑Fi.
//  - The first non‑nil mediaPeer is latched so streaming continues even
//    if the Host app is backgrounded or later clears the App Group keys.
//

import Foundation
import Network
import OSLog
import BeamCore

actor UDPMediaSender {

    // MARK: - Singleton

    static let shared = UDPMediaSender()

    // MARK: - State

    private var conn: NWConnection?
    private var currentDest: (host: String, port: UInt16)?
    private var seq: UInt32 = 0

    /// Once true, we keep sending to the last known Viewer peer even if
    /// BeamConfig.getMediaPeer() later returns nil (e.g. Host expired it).
    private var hasLatchedMediaPeer = false

    private let log = Logger(subsystem: BeamConfig.subsystemExt,
                             category: "udp-send")

    // Conservative payload to avoid IP fragmentation on Wi‑Fi.
    private let maxUDPPayload = 1200
    private let fixedHeaderBytes = 20 // H264Wire fixed BE header size

    // MARK: - Lifecycle

    /// Called when the ReplayKit broadcast starts.
    func start() async {
        await reconnectIfNeeded(reason: "start")
    }

    /// Called when the ReplayKit broadcast finishes.
    func stop() async {
        await closeConnection(resetDest: true)
    }

    // MARK: - Public API

    func sendAVCC(
        width: Int,
        height: Int,
        avcc: Data,
        paramSets: H264Wire.ParamSets?,
        isKeyframe: Bool
    ) async {
        guard await ensureConnection() else { return }

        // Param-set blob for keyframes (SPS/PPS)
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

        // Split the AVCC data into parts that fit within our UDP budget.
        let max0 = maxUDPPayload - fixedHeaderBytes - (cfg.isEmpty ? 0 : cfg.count)
        let chunk0 = max(0, min(max0, avcc.count))
        let remaining = avcc.count - chunk0

        let perPart = maxUDPPayload - fixedHeaderBytes
        let extraParts = (remaining > 0)
            ? Int(ceil(Double(remaining) / Double(perPart)))
            : 0

        let partCount = 1 + extraParts

        // Part 0
        do {
            let h = H264Wire.Header(
                seq: seq,
                partIndex: 0,
                partCount: UInt16(partCount),
                flags: flags,
                width: UInt16(max(0, min(width, Int(UInt16.max)))),
                height: UInt16(max(0, min(height, Int(UInt16.max)))),
                configBytes: UInt16(cfg.count)
            )

            var pkt = encodeHeaderBE(h)
            if !cfg.isEmpty {
                pkt.append(cfg)
            }
            if chunk0 > 0 {
                pkt.append(avcc.prefix(chunk0))
            }

            try await sendPacket(pkt)
        } catch {
            log.error("send part0 failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Remaining parts
        var sent = chunk0
        var idx: UInt16 = 1

        while sent < avcc.count {
            let n = min(perPart, avcc.count - sent)

            let h = H264Wire.Header(
                seq: seq,
                partIndex: idx,
                partCount: UInt16(partCount),
                flags: flags,
                width: UInt16(max(0, min(width, Int(UInt16.max)))),
                height: UInt16(max(0, min(height, Int(UInt16.max)))),
                configBytes: 0
            )

            var pkt = encodeHeaderBE(h)
            pkt.append(avcc.subdata(in: sent..<(sent + n)))

            do {
                try await sendPacket(pkt)
            } catch {
                log.error("send part \(idx) failed: \(error.localizedDescription, privacy: .public)")
                return
            }

            sent += n
            idx &+= 1
        }

        seq &+= 1
    }

    // MARK: - Connection management

    private func ensureConnection() async -> Bool {
        // Always re-evaluate the destination so we can switch from Host→Viewer
        // once BeamConfig.mediaPeer is published.
        let reason = (conn == nil) ? "no-conn" : "check"
        await reconnectIfNeeded(reason: reason)
        return conn != nil
    }

    /// Decide where to send:
    ///  - If a mediaPeer exists, send directly to Viewer (Wi‑Fi).
    ///  - Else, while we have NOT latched a peer, send to Host loopback.
    ///  - Else (latched but peer missing in UserDefaults), keep using the
    ///    last latched destination so Host going to background does not
    ///    break streaming.
    private func reconnectIfNeeded(reason: String) async {
        var target: (host: String, port: UInt16)?

        if let peer = BeamConfig.getMediaPeer() {
            // Direct Viewer endpoint (ip:port) as seen by Host.
            target = (peer.host, peer.port)
            hasLatchedMediaPeer = true
        } else if hasLatchedMediaPeer, let cur = currentDest {
            // Keep sending to the last known Viewer even if Host later clears
            // the App Group keys.
            target = cur
        } else if let port = BeamConfig.getBroadcastUDPPort() {
            // Fallback: send to Host’s local UDP listener for initial pairing
            // or preview before a Viewer is active.
            target = ("127.0.0.1", port)
        }

        guard let dest = target else {
            return
        }

        // No-op if destination is unchanged and we still have a connection.
        if let cur = currentDest,
           cur.host == dest.host,
           cur.port == dest.port,
           conn != nil {
            return
        }

        currentDest = dest
        await connect(to: dest)

        log.notice(
            "Uplink dest → \(dest.host, privacy: .public):\(dest.port) (\(reason, privacy: .public))"
        )
    }

    private func connect(to dest: (host: String, port: UInt16)) async {
        // Tear down any previous connection but DO NOT reset currentDest or
        // the latched peer flag; those are controlled by reconnectIfNeeded().
        await closeConnection(resetDest: false)

        guard let nwPort = NWEndpoint.Port(rawValue: dest.port) else {
            return
        }

        let host = NWEndpoint.Host(dest.host)
        let params = NWParameters.udp
        params.includePeerToPeer = false

        // For loopback, keep traffic on lo0; for real peers, prefer Wi‑Fi.
        if dest.host == "127.0.0.1" || dest.host == "::1" || dest.host == "localhost" {
            params.requiredInterfaceType = .loopback
        } else {
            params.requiredInterfaceType = .wifi
        }

        let c = NWConnection(host: host, port: nwPort, using: params)
        conn = c

        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .ready:
                self.log.notice(
                    "UDP uplink ready → \(dest.host, privacy: .public):\(dest.port)"
                )
            case .failed(let err):
                self.log.error(
                    "UDP uplink failed: \(err.localizedDescription, privacy: .public)"
                )
                // Network hiccup – drop the socket; destination stays latched
                // so the next frame will reconnect.
                Task { await self.closeConnection(resetDest: false) }
            case .cancelled:
                self.log.notice("UDP uplink cancelled")
                Task { await self.closeConnection(resetDest: false) }
            default:
                break
            }
        }

        c.start(queue: .main)
    }

    private func closeConnection(resetDest: Bool) async {
        conn?.cancel()
        conn = nil

        if resetDest {
            currentDest = nil
            hasLatchedMediaPeer = false
        }
    }

    // MARK: - Sending

    private func sendPacket(_ data: Data) async throws {
        guard let c = conn else {
            throw NSError(
                domain: "UDPMediaSender",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No UDP connection"]
            )
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            c.send(content: data, completion: .contentProcessed { error in
                if let e = error {
                    cont.resume(throwing: e)
                } else {
                    cont.resume()
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
}
