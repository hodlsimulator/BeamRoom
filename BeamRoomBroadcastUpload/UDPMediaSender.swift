//
//  UDPMediaSender.swift
//  BeamRoomHost
//
//  Created by . . on 9/27/25.
//
//  Broadcast Upload extension peer + UDP sender.
//  Reads the Host-published active peer (ip:port) from the App Group and
//  sends M4 H.264 datagrams (via BeamCore.H264Wire) to that peer.
//  If there is no fresh peer (seen within 6 seconds), we don’t send.
//

import Foundation
import Network
import BeamCore // BeamConfig, H264Wire, Data+BE, BeamLog

actor UDPMediaSender {

    static let shared = UDPMediaSender()

    // MARK: - State
    private var conn: NWConnection?
    private var currentKey: String? // "host:port"
    private var pollTimer: DispatchSourceTimer?
    private var seq: UInt32 = 0

    // MARK: - Lifecycle
    func start() {
        startPeerPolling()
    }

    func stop() {
        pollTimer?.cancel(); pollTimer = nil
        conn?.cancel(); conn = nil
        currentKey = nil
        seq = 0
    }

    // MARK: - Sending (M4 wire)
    /// Build BMRV datagrams from raw AVCC and send them. Safe (Data + scalars only).
    func sendAVCC(width: Int,
                  height: Int,
                  avcc: Data,
                  paramSets: H264Wire.ParamSets?,
                  isKeyframe: Bool,
                  mtu: Int = 1200) {
        guard let c = conn, !avcc.isEmpty else { return }

        // Flags + optional config blob
        var flags = H264Wire.Flags()
        if isKeyframe { flags.insert(.keyframe) }
        let cfg = (paramSets != nil) ? H264Wire.encodeParamSets(paramSets!) : Data()
        if !cfg.isEmpty { flags.insert(.hasParamSet) }

        let fixed = H264Wire.fixedHeaderBytes
        let firstBudget = mtu - fixed - cfg.count
        let restBudget  = mtu - fixed
        guard firstBudget > 0 && restBudget > 0 else { return }

        let total = avcc.count
        var parts = 1
        if total > firstBudget {
            let remain = total - firstBudget
            let extra = (remain + (restBudget - 1)) / restBudget
            parts = 1 + max(0, extra)
        }

        seq &+= 1
        let w16 = UInt16(clamping: width)
        let h16 = UInt16(clamping: height)

        var offset = 0
        for idx in 0..<parts {
            let carryCfg = (idx == 0 && !cfg.isEmpty)
            let budget = carryCfg ? firstBudget : restBudget
            let take = min(budget, total - offset)
            let body = avcc.subdata(in: offset..<(offset + take))
            offset += take

            let header = H264Wire.Header(
                seq: seq,
                partIndex: UInt16(idx),
                partCount: UInt16(parts),
                flags: flags,
                width: w16,
                height: h16,
                configBytes: UInt16(carryCfg ? cfg.count : 0)
            )

            var packet = makeHeaderBE(header)
            if carryCfg { packet.append(cfg) }
            packet.append(body)

            c.send(content: packet, completion: .contentProcessed { _ in })
        }
    }

    // MARK: - Peer tracking (Host → Extension via BeamConfig)
    private func startPeerPolling() {
        pollTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 1.0)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.refreshPeer() }
        }
        t.resume()
        pollTimer = t
    }

    private func refreshPeer() {
        guard let peer = BeamConfig.getMediaPeer() else {
            if conn != nil {
                BeamLog.info("Sender: clearing peer", tag: "host")
                conn?.cancel(); conn = nil; currentKey = nil
            }
            return
        }

        let key = "\(peer.host):\(peer.port)"
        if key == currentKey, conn != nil { return }

        // Reconnect to new peer
        conn?.cancel(); conn = nil
        currentKey = key

        guard let nwPort = NWEndpoint.Port(rawValue: peer.port) else {
            currentKey = nil
            return
        }

        let params = NWParameters.udp
        params.requiredInterfaceType = .wifi
        params.includePeerToPeer = false

        let c = NWConnection(host: NWEndpoint.Host(peer.host), port: nwPort, using: params)
        c.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            guard let self else { return }
            switch state {
            case .ready:
                BeamLog.info("Sender: UDP ready → \(key)", tag: "host")
                // Optional hello so Host logs first datagram
                c.send(content: Data([0x42,0x52,0x48,0x49,0x21]), completion: .contentProcessed { _ in })
            case .failed(let err):
                BeamLog.error("Sender failed: \(err.localizedDescription)", tag: "host")
                Task { await self.disconnect() }
            case .cancelled:
                Task { await self.disconnect() }
            default:
                break
            }
        }
        c.start(queue: .main)
        conn = c
    }

    private func disconnect() {
        conn?.cancel(); conn = nil
        currentKey = nil
    }

    // MARK: - Helpers
    /// Build the 20-byte big-endian BMRV header.
    private func makeHeaderBE(_ h: H264Wire.Header) -> Data {
        var out = Data(capacity: H264Wire.fixedHeaderBytes)
        out.appendBE(H264Wire.magic)           // u32 'BMRV'
        out.appendBE(h.seq)                    // u32 seq
        out.appendBE(h.partIndex)              // u16 partIndex
        out.appendBE(h.partCount)              // u16 partCount
        out.appendBE(h.flags.rawValue)         // u16 flags
        out.appendBE(h.width)                  // u16 width
        out.appendBE(h.height)                 // u16 height
        out.appendBE(h.configBytes)            // u16 configBytes (only in part 0 when hasParamSet)
        return out
    }
}
