//
//  UDPMediaSender.swift
//  BeamRoomHost
//
//  Created by . . on 10/31/25.
//

import Foundation
import Network
import OSLog
import BeamCore

actor UDPMediaSender {

    static let shared = UDPMediaSender()

    private var conn: NWConnection?
    private var currentDest: (host: String, port: UInt16)?
    private var seq: UInt32 = 0
    private let log = Logger(subsystem: BeamConfig.subsystemExt, category: "udp-send")

    private let maxUDPPayload = 1200
    private let fixedHeaderBytes = 20

    func start() async { await reconnectIfNeeded(reason: "start") }
    func stop() async { conn?.cancel(); conn = nil }

    func sendAVCC(width: Int, height: Int, avcc: Data, paramSets: H264Wire.ParamSets?, isKeyframe: Bool) async {
        guard await ensureConnection() else { return }

        var cfg = Data()
        var flags = H264Wire.Flags()
        if isKeyframe { flags.insert(.keyframe) }
        if isKeyframe, let ps = paramSets {
            cfg = H264Wire.encodeParamSets(ps)
            if !cfg.isEmpty { flags.insert(.hasParamSet) }
        }

        let max0 = maxUDPPayload - fixedHeaderBytes - (cfg.isEmpty ? 0 : cfg.count)
        let chunk0 = max(0, min(max0, avcc.count))
        let remaining = avcc.count - chunk0
        let perPart = maxUDPPayload - fixedHeaderBytes
        let extraParts = (remaining > 0) ? Int(ceil(Double(remaining) / Double(perPart))) : 0
        let partCount = 1 + extraParts

        // part 0
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
            if !cfg.isEmpty { pkt.append(cfg) }
            if chunk0 > 0 { pkt.append(avcc.prefix(chunk0)) }
            try await sendPacket(pkt)
        } catch {
            log.error("send part0 failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        // remainder
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
            do { try await sendPacket(pkt) } catch {
                log.error("send part \(idx) failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            sent += n
            idx &+= 1
        }

        seq &+= 1
    }

    // MARK: internals

    private func ensureConnection() async -> Bool {
        if conn == nil { await reconnectIfNeeded(reason: "no-conn") }
        return conn != nil
    }

    private func reconnectIfNeeded(reason: String) async {
        guard let port = BeamConfig.getBroadcastUDPPort() else { return }
        let dest = (host: "127.0.0.1", port: port)
        if let cur = currentDest, cur.host == dest.host && cur.port == dest.port { return }
        currentDest = dest
        await connect(to: dest)
        log.notice("Uplink dest → \(dest.host, privacy: .public):\(dest.port) (\(reason, privacy: .public))")
    }

    private func connect(to dest: (host: String, port: UInt16)) async {
        conn?.cancel(); conn = nil

        guard let nwPort = NWEndpoint.Port(rawValue: dest.port) else { return }
        let host = NWEndpoint.Host(dest.host)

        let params = NWParameters.udp
        params.includePeerToPeer = false

        let c = NWConnection(host: host, port: nwPort, using: params)
        conn = c

        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log.notice("UDP uplink ready → \(dest.host, privacy: .public):\(dest.port)")
            case .failed(let err):
                self.log.error("UDP uplink failed: \(err.localizedDescription, privacy: .public)")
                Task { await self.stop() }
            case .cancelled:
                self.log.notice("UDP uplink cancelled")
                Task { await self.stop() }
            default:
                break
            }
        }

        c.start(queue: .main)
    }

    private func sendPacket(_ data: Data) async throws {
        guard let c = conn else { throw NSError(domain: "UDPMediaSender", code: -1) }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            c.send(content: data, completion: .contentProcessed { err in
                if let e = err { cont.resume(throwing: e) } else { cont.resume() }
            })
        }
    }

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
