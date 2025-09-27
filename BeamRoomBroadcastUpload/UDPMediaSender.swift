//
//  UDPMediaSender.swift
//  BeamRoomHost
//
//  Created by . . on 9/27/25.
//
//  Broadcast Upload extension → sends AVCC H.264 over UDP directly to the
//  active Viewer peer (ip:port) that the Host publishes into the App Group.
//

import Foundation
import Network
import OSLog
import BeamCore

actor UDPMediaSender {

    static let shared = UDPMediaSender()

    // MARK: State
    private var conn: NWConnection?
    private var currentPeer: (host: String, port: UInt16)?
    private var seq: UInt32 = 0
    private var observing = false

    private let log = Logger(subsystem: BeamConfig.subsystemExt, category: "udp-send")

    // Conservative payload to avoid IP fragmentation on Wi-Fi.
    private let maxUDPPayload = 1200
    private let fixedHeaderBytes = 20 // H264Wire fixed BE header size

    // MARK: Lifecycle
    func start() async {
        if !observing {
            startObservingPeerChanges()
            observing = true
        }
        await reconnectIfNeeded(reason: "start")
    }

    func stop() async {
        stopObservingPeerChanges()
        observing = false
        await disconnect()
    }

    // MARK: Sending
    func sendAVCC(width: Int, height: Int, avcc: Data, paramSets: H264Wire.ParamSets?, isKeyframe: Bool) async {
        guard await ensureConnection() else { return }

        // Param-set blob for keyframes (SPS/PPS)
        var cfg = Data()
        var flags = H264Wire.Flags()
        if isKeyframe { flags.insert(.keyframe) }
        if isKeyframe, let ps = paramSets {
            cfg = H264Wire.encodeParamSets(ps)
            if !cfg.isEmpty { flags.insert(.hasParamSet) }
        }

        // Split the AVCC data into parts that fit within our UDP budget
        let max0 = maxUDPPayload - fixedHeaderBytes - (cfg.isEmpty ? 0 : cfg.count)
        let chunk0 = max(0, min(max0, avcc.count))
        let remaining = avcc.count - chunk0
        let perPart = maxUDPPayload - fixedHeaderBytes
        let extraParts = (remaining > 0) ? Int(ceil(Double(remaining) / Double(perPart))) : 0
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
            if !cfg.isEmpty { pkt.append(cfg) }
            if chunk0 > 0 { pkt.append(avcc.prefix(chunk0)) }
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

    // MARK: Internals

    private func ensureConnection() async -> Bool {
        if conn == nil {
            await reconnectIfNeeded(reason: "no-conn")
        }
        return conn != nil
    }

    private func reconnectIfNeeded(reason: String) async {
        let peer = BeamConfig.getMediaPeer()
        if peer == nil { return }
        if let cur = currentPeer, cur.host == peer!.host && cur.port == peer!.port { return }
        currentPeer = peer
        await connect(to: peer!)
        log.notice("Peer changed → \(peer!.host, privacy: .public):\(peer!.port) (\(reason, privacy: .public))")
    }

    private func connect(to peer: (host: String, port: UInt16)) async {
        await disconnect()

        guard let nwPort = NWEndpoint.Port(rawValue: peer.port) else { return }
        let host = NWEndpoint.Host(peer.host)
        let params = NWParameters.udp
        params.requiredInterfaceType = .wifi
        params.includePeerToPeer = false

        let c = NWConnection(host: host, port: nwPort, using: params)
        conn = c

        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log.notice("UDP ready → \(peer.host, privacy: .public):\(peer.port)")
            case .failed(let err):
                self.log.error("UDP failed: \(err.localizedDescription, privacy: .public)")
                Task { await self.disconnect() }
            case .cancelled:
                self.log.notice("UDP cancelled")
                Task { await self.disconnect() }
            default:
                break
            }
        }
        c.start(queue: .main)
    }

    private func disconnect() async {
        conn?.cancel()
        conn = nil
    }

    private func sendPacket(_ data: Data) async throws {
        guard let c = conn else { throw NSError(domain: "UDPMediaSender", code: -1) }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            c.send(content: data, completion: .contentProcessed { err in
                if let e = err { cont.resume(throwing: e) } else { cont.resume() }
            })
        }
    }

    // MARK: Darwin notify for peer changes
    private func startObservingPeerChanges() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName(BeamConfig.mediaPeerDarwinName as CFString)
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let me = Unmanaged<UDPMediaSender>.fromOpaque(observer).takeUnretainedValue()
                Task { await me.reconnectIfNeeded(reason: "darwin") }
            },
            name.rawValue,
            nil,
            .deliverImmediately
        )
    }

    private func stopObservingPeerChanges() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: Header encode (local to avoid visibility issues)
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
