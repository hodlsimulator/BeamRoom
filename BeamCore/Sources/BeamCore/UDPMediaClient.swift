//
//  UDPMediaClient.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  Viewer-side UDP media receiver: supports M3 test frames (BGRA) + M4 H.264 video.
//

import Foundation
import Combine
import Network
import OSLog
import CoreGraphics

private let mediaOS = Logger(subsystem: BeamConfig.subsystemViewer, category: "udp-media")

private func udpIfaceTypeString(_ t: NWInterface.InterfaceType) -> String {
    switch t {
    case .wifi: return "wifi"
    case .cellular: return "cellular"
    case .wiredEthernet: return "wired"
    case .loopback: return "loop"
    case .other: return "other"
    @unknown default: return "other"
    }
}

private func udpPathSummary(_ path: NWPath?) -> String {
    guard let p = path else { return "path=?" }
    let ifs = p.availableInterfaces.map { udpIfaceTypeString($0.type) }.joined(separator: ",")
    let ok = (p.status == .satisfied) ? "ok" : "fail"
    return "path=\(ok),ifs=\(ifs)"
}

@MainActor
public final class UDPMediaClient: ObservableObject {
    public struct Stats: Equatable {
        public var frames: UInt64 = 0
        public var fps: Double = 0
        public var kbps: Double = 0
        public var lastSeq: UInt32 = 0
        public var drops: UInt64 = 0
        public init() {}
    }

    @Published public private(set) var lastImage: CGImage?
    @Published public private(set) var stats: Stats = .init()

    private var conn: NWConnection?
    private var bytesInWindow: Int = 0
    private var framesInWindow: Int = 0
    private var windowStart = Date()

    private var connectedKey: String?
    private var lastTarget: (host: NWEndpoint.Host, port: UInt16)?
    private var autoReconnectWanted = false
    private var reconnectTimer: DispatchSourceTimer?

    // Diagnostics
    private var sawAnyDatagram = false
    private var sawFirstValidFrame = false
    private var shortHeaderCount: UInt64 = 0
    private var badMagicCount: UInt64 = 0
    private var badSizeCount: UInt64 = 0
    private var lastSummaryAt = Date()
    private var afterReadyWarnTimer: DispatchSourceTimer?

    // Keep-alive so the Host retains our peer mapping.
    private var keepaliveTimer: DispatchSourceTimer?
    private let keepaliveInterval: TimeInterval = 2.5

    // M4 video
    private let assembler = H264Assembler()
    private let decoder = H264Decoder()

    public init() {}

    // MARK: Public API

    public func armAutoReconnect() { autoReconnectWanted = true }
    public func disarmAutoReconnect() { autoReconnectWanted = false; cancelReconnect() }

    public func connect(toHost host: NWEndpoint.Host, port: UInt16) {
        let key = "\(String(describing: host)):\(port)"
        if connectedKey == key {
            BeamLog.debug("UDP connect de-dupe → already \(key)", tag: "viewer")
            return
        }
        disconnect() // tear down any previous socket (will not schedule reconnect because we immediately reconnect)
        lastTarget = (host, port)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            BeamLog.error("UDP connect failed: invalid port \(port)", tag: "viewer")
            return
        }

        let params = NWParameters.udp
        params.requiredInterfaceType = .wifi
        params.includePeerToPeer = false

        let c = NWConnection(host: host, port: nwPort, using: params)
        conn = c
        connectedKey = key
        BeamLog.info("UDP connect → \(String(describing: host)):\(port)", tag: "viewer")

        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            let ps = udpPathSummary(c.currentPath)
            switch state {
            case .setup:
                BeamLog.debug("UDP state=setup (\(ps))", tag: "viewer")
            case .preparing:
                BeamLog.debug("UDP state=preparing (\(ps))", tag: "viewer")
            case .ready:
                mediaOS.info("UDP ready → \(String(describing: host)):\(port)")
                BeamLog.info("UDP ready (\(ps)) → send hello & recv", tag: "viewer")
                Task { @MainActor in
                    self.sendHello()
                    self.startAfterReadyWarnTimer(host: host, port: port)
                    self.startKeepalives()
                    self.receiveLoop()
                }
            case .waiting(let err):
                BeamLog.warn("UDP waiting: \(err.localizedDescription) (\(ps))", tag: "viewer")
            case .failed(let err):
                mediaOS.error("UDP failed: \(err.localizedDescription, privacy: .public)")
                BeamLog.error("UDP failed: \(err.localizedDescription) (\(ps))", tag: "viewer")
                Task { @MainActor in
                    self.disconnect()
                }
            case .cancelled:
                mediaOS.notice("UDP cancelled")
                BeamLog.warn("UDP cancelled (\(ps))", tag: "viewer")
                Task { @MainActor in
                    self.disconnect()
                }
            @unknown default:
                BeamLog.debug("UDP state=\(String(describing: state)) (\(ps))", tag: "viewer")
            }
        }

        c.start(queue: .main)
    }

    public func disconnect() {
        afterReadyWarnTimer?.cancel(); afterReadyWarnTimer = nil
        stopKeepalives()
        conn?.cancel(); conn = nil
        connectedKey = nil

        lastImage = nil
        stats = .init()
        bytesInWindow = 0
        framesInWindow = 0

        // Reset diagnostics
        sawAnyDatagram = false
        sawFirstValidFrame = false
        shortHeaderCount = 0
        badMagicCount = 0
        badSizeCount = 0
        lastSummaryAt = Date()

        assembler.reset()
        decoder.invalidate()

        BeamLog.info("UDP disconnected", tag: "viewer")

        // Auto-reconnect (network errors) if asked and we still know where to go
        if autoReconnectWanted, let target = lastTarget {
            scheduleReconnect(to: target)
        }
    }

    // MARK: IO

    private func sendHello() {
        guard let c = conn else { return }
        let hello = Data([0x42, 0x52, 0x48, 0x49, 0x21]) // "BRHI!"
        c.send(content: hello, completion: .contentProcessed { maybeErr in
            if let e = maybeErr {
                BeamLog.error("UDP hello send error: \(e.localizedDescription)", tag: "viewer")
            } else {
                mediaOS.debug("UDP hello → sent")
                BeamLog.debug("UDP hello → sent (5 bytes)", tag: "viewer")
            }
        })
    }

    private func receiveLoop() {
        guard let c = conn else { return }
        c.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }

            if let d = data, !d.isEmpty {
                if !self.sawAnyDatagram {
                    self.sawAnyDatagram = true
                    BeamLog.info("UDP rx first datagram: \(d.count) bytes", tag: "viewer")
                    self.afterReadyWarnTimer?.cancel(); self.afterReadyWarnTimer = nil
                }
                self.handleDatagram(d)
            }

            if let error {
                mediaOS.error("UDP recv error: \(error.localizedDescription, privacy: .public)")
                BeamLog.error("UDP recv error: \(error.localizedDescription)", tag: "viewer")
                Task { @MainActor in self.disconnect() }
                return
            }

            self.receiveLoop()
        }
    }

    private func handleDatagram(_ data: Data) {
        // H.264 over UDP (M4) only. Ignore legacy M3 BGRA test frames.
        guard let unit = assembler.ingest(datagram: data) else {
            return
        }

        // Basic loss / throughput stats
        if stats.frames > 0, unit.seq > stats.lastSeq + 1 {
            stats.drops += UInt64(unit.seq - stats.lastSeq - 1)
        }
        stats.lastSeq = unit.seq
        stats.frames &+= 1

        bytesInWindow += data.count
        framesInWindow &+= 1

        let now = Date()
        let elapsed = now.timeIntervalSince(windowStart)
        if elapsed >= 1.0 {
            stats.fps = Double(framesInWindow) / elapsed
            stats.kbps = Double(bytesInWindow * 8) / elapsed / 1000.0
            windowStart = now
            bytesInWindow = 0
            framesInWindow = 0

            BeamLog.debug(
                String(
                    format: "UDP video rx ~ %.1f fps • %.0f kbps • frames %llu • drops %llu",
                    stats.fps, stats.kbps, stats.frames, stats.drops
                ),
                tag: "viewer"
            )
        }

        let w = unit.width
        let h = unit.height
        let s = unit.seq

        decoder.decode(avcc: unit.avccData, paramSets: unit.paramSets) { [weak self] cg in
            guard let self else { return }
            if let cg {
                if !self.sawFirstValidFrame {
                    self.sawFirstValidFrame = true
                    BeamLog.info(
                        "UDP first valid H.264 frame ✓ \(w)x\(h) (seq \(s))",
                        tag: "viewer"
                    )
                }
                self.lastImage = cg
            }
        }
    } 

    // MARK: Helpers

    private func maybeSummarise(extra: String? = nil) {
        let now = Date()
        if now.timeIntervalSince(lastSummaryAt) >= 1.0 {
            lastSummaryAt = now
            var bits: [String] = []
            if shortHeaderCount > 0 { bits.append("short \(shortHeaderCount)") }
            if badMagicCount > 0 { bits.append("badMagic \(badMagicCount)") }
            if badSizeCount > 0 { bits.append("badSize \(badSizeCount)") }
            if !bits.isEmpty {
                BeamLog.info("UDP rx rejects: " + bits.joined(separator: " • ") + (extra != nil ? " • \(extra!)" : ""), tag: "viewer")
            }
        }
    }

    private func startAfterReadyWarnTimer(host: NWEndpoint.Host, port: UInt16) {
        afterReadyWarnTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 2.0, repeating: 3.0)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            if !self.sawAnyDatagram {
                BeamLog.warn("UDP ready but still no datagrams from \(String(describing: host)):\(port)", tag: "viewer")
            } else {
                self.afterReadyWarnTimer?.cancel(); self.afterReadyWarnTimer = nil
            }
        }
        t.resume()
        afterReadyWarnTimer = t
    }

    private func startKeepalives() {
        stopKeepalives()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + keepaliveInterval, repeating: keepaliveInterval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.sendHello()
        }
        t.resume()
        keepaliveTimer = t
    }

    private func stopKeepalives() {
        keepaliveTimer?.cancel(); keepaliveTimer = nil
    }

    private func scheduleReconnect(to target: (host: NWEndpoint.Host, port: UInt16)) {
        cancelReconnect()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.5)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.connect(toHost: target.host, port: target.port)
        }
        t.resume()
        reconnectTimer = t
    }

    private func cancelReconnect() {
        reconnectTimer?.cancel(); reconnectTimer = nil
    }
}
