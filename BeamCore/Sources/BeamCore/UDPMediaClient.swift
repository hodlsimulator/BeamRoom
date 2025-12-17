//
//  UDPMediaClient.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
//  Viewer-side UDP media receiver: supports M4 H.264 video.
//

import Foundation
import Combine
import Network
import OSLog
import CoreGraphics

private let mediaOS = Logger(
    subsystem: BeamConfig.subsystemViewer,
    category: "udp-media"
)

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
    let ifs = p.availableInterfaces
        .map { udpIfaceTypeString($0.type) }
        .joined(separator: ",")
    let ok = (p.status == .satisfied) ? "ok" : "fail"
    return "path=\(ok),ifs=\(ifs)"
}

@MainActor
public final class UDPMediaClient: ObservableObject {

    // MARK: - Public stats model

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

    // MARK: - Connection state

    private var conn: NWConnection?
    private var bytesInWindow: Int = 0
    private var framesInWindow: Int = 0
    private var windowStart = Date()
    private var connectedKey: String?
    private var lastTarget: (host: NWEndpoint.Host, port: UInt16)?

    // Auto-reconnect after network errors only
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

    // More aggressive keepalive helps preserve the mapping through backgrounding / AWDL quirks.
    private let keepaliveInterval: TimeInterval = 1.0

    // NEW: Silence-based liveness watchdog (UDP can stall without errors).
    private var livenessTimer: DispatchSourceTimer?
    private let livenessInterval: TimeInterval = 1.0
    private let noDatagramTimeoutAfterReady: TimeInterval = 6.0
    private let noDatagramTimeoutAfterData: TimeInterval = 4.0
    private var readyAt: Date?
    private var lastDatagramAt: Date?
    private var reachedReady: Bool = false

    // M4 video pipeline
    private let assembler = H264Assembler()
    private let decoder = H264Decoder()

    public init() {}

    // MARK: - Public API

    /// Enable automatic UDP reconnect after *network* errors (and liveness timeouts).
    public func armAutoReconnect() {
        autoReconnectWanted = true
    }

    /// Disable automatic UDP reconnect and cancel any pending retry.
    public func disarmAutoReconnect() {
        autoReconnectWanted = false
        cancelReconnect()
    }

    /// Connects to a specific Host + UDP port.
    ///
    /// If this is a retarget (for example, Host restarted with a new port),
    /// this tears down any previous socket **without** scheduling auto-reconnect,
    /// then connects to the new destination.
    public func connect(toHost host: NWEndpoint.Host, port: UInt16) {
        let key = "\(String(describing: host)):\(port)"
        if connectedKey == key {
            BeamLog.debug("UDP connect de-dupe → already \(key)", tag: "viewer")
            return
        }

        // Remember the new target first so error-based auto-reconnect uses the latest Host+port.
        lastTarget = (host, port)

        // This is a manual retarget: cancel any pending auto-reconnect and
        // tear down the old socket without scheduling a new reconnect.
        cancelReconnect()
        disconnectInternal(scheduleReconnect: false)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            BeamLog.error("UDP connect failed: invalid port \(port)", tag: "viewer")
            return
        }

        readyAt = nil
        lastDatagramAt = nil
        reachedReady = false

        let params = NWParameters.udp

        // Allow infra Wi‑Fi + peer-to-peer (AWDL / Wi‑Fi Aware), avoid cellular.
        params.includePeerToPeer = true
        params.prohibitedInterfaceTypes = [.cellular]

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
                BeamLog.info("UDP state=ready (\(ps)) → send hello & recv", tag: "viewer")

                Task { @MainActor in
                    self.reachedReady = true
                    self.readyAt = Date()
                    self.lastDatagramAt = nil

                    self.sendHello()
                    self.startAfterReadyWarnTimer(host: host, port: port)
                    self.startKeepalives()
                    self.startLivenessWatch()
                    self.receiveLoop()
                }

            case .waiting(let err):
                BeamLog.warn("UDP waiting: \(err.localizedDescription) (\(ps))", tag: "viewer")

            case .failed(let err):
                mediaOS.error("UDP failed: \(err.localizedDescription, privacy: .public)")
                BeamLog.error("UDP failed: \(err.localizedDescription) (\(ps))", tag: "viewer")
                Task { @MainActor in
                    self.disconnectInternal(scheduleReconnect: true)
                }

            case .cancelled:
                mediaOS.notice("UDP cancelled")
                BeamLog.warn("UDP cancelled (\(ps))", tag: "viewer")
                Task { @MainActor in
                    self.disconnectInternal(scheduleReconnect: true)
                }

            @unknown default:
                BeamLog.debug("UDP state=\(String(describing: state)) (\(ps))", tag: "viewer")
            }
        }

        // React to path changes (e.g. after a phone call or Wi‑Fi blip).
        c.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let summary = udpPathSummary(path)
            mediaOS.debug("UDP pathUpdate → \(summary)")

            // If the path is no longer satisfied, tear down and let the existing
            // auto-reconnect logic bring the socket back on a fresh path.
            if path.status == .unsatisfied {
                BeamLog.warn("UDP path unsatisfied; forcing reconnect (\(summary))", tag: "viewer")
                Task { @MainActor in
                    self.disconnectInternal(scheduleReconnect: true)
                }
            }
        }

        c.start(queue: .main)
    }

    /// Manual disconnect from the Viewer / UI.
    ///
    /// This *never* schedules auto-reconnect, even if `armAutoReconnect()`
    /// was called earlier.
    public func disconnect() {
        disconnectInternal(scheduleReconnect: false)
    }

    // MARK: - Internal teardown

    private func disconnectInternal(scheduleReconnect shouldReconnect: Bool) {
        // Timers
        stopLivenessWatch()

        afterReadyWarnTimer?.cancel()
        afterReadyWarnTimer = nil

        stopKeepalives()

        conn?.cancel()
        conn = nil
        connectedKey = nil

        reachedReady = false
        readyAt = nil
        lastDatagramAt = nil

        // Visible state
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

        // Only schedule auto-reconnect on error-driven teardown.
        if shouldReconnect, autoReconnectWanted, let target = lastTarget {
            scheduleReconnect(to: target)
        }
    }

    // MARK: - IO

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
                self.lastDatagramAt = Date()

                if !self.sawAnyDatagram {
                    self.sawAnyDatagram = true
                    BeamLog.info("UDP rx first datagram: \(d.count) bytes", tag: "viewer")
                    self.afterReadyWarnTimer?.cancel()
                    self.afterReadyWarnTimer = nil
                }

                self.handleDatagram(d)
            }

            if let error {
                mediaOS.error("UDP recv error: \(error.localizedDescription, privacy: .public)")
                BeamLog.error("UDP recv error: \(error.localizedDescription)", tag: "viewer")
                Task { @MainActor in
                    self.disconnectInternal(scheduleReconnect: true)
                }
                return
            }

            self.receiveLoop()
        }
    }

    private func handleDatagram(_ data: Data) {
        // H.264 over UDP (M4) only. Ignore legacy M3 BGRA test frames.
        guard let unit = assembler.ingest(datagram: data) else { return }

        // Loss / throughput stats
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
                    BeamLog.info("UDP first valid H.264 frame ✓ \(w)x\(h) (seq \(s))", tag: "viewer")
                }
                self.lastImage = cg
            }
        }
    }

    // MARK: - Diagnostics helpers

    private func maybeSummarise(extra: String? = nil) {
        let now = Date()
        if now.timeIntervalSince(lastSummaryAt) >= 1.0 {
            lastSummaryAt = now

            var bits: [String] = []
            if shortHeaderCount > 0 { bits.append("short \(shortHeaderCount)") }
            if badMagicCount > 0 { bits.append("badMagic \(badMagicCount)") }
            if badSizeCount > 0 { bits.append("badSize \(badSizeCount)") }

            if !bits.isEmpty {
                let suffix = extra.map { " • \($0)" } ?? ""
                BeamLog.info("UDP rx rejects: " + bits.joined(separator: " • ") + suffix, tag: "viewer")
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
                BeamLog.warn(
                    "UDP ready but still no datagrams from \(String(describing: host)):\(port)",
                    tag: "viewer"
                )
            } else {
                self.afterReadyWarnTimer?.cancel()
                self.afterReadyWarnTimer = nil
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
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
    }

    // MARK: - Liveness watchdog (silence-based)

    private func startLivenessWatch() {
        stopLivenessWatch()

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + livenessInterval, repeating: livenessInterval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.livenessTick()
        }
        t.resume()
        livenessTimer = t
    }

    private func stopLivenessWatch() {
        livenessTimer?.cancel()
        livenessTimer = nil
    }

    private func livenessTick() {
        guard autoReconnectWanted else { return }
        guard reachedReady, conn != nil else { return }

        let now = Date()

        if !sawAnyDatagram {
            if let readyAt, now.timeIntervalSince(readyAt) > noDatagramTimeoutAfterReady {
                BeamLog.warn(
                    "UDP liveness: ready but no datagrams in \(Int(noDatagramTimeoutAfterReady))s → reconnect",
                    tag: "viewer"
                )
                disconnectInternal(scheduleReconnect: true)
            }
            return
        }

        if let last = lastDatagramAt, now.timeIntervalSince(last) > noDatagramTimeoutAfterData {
            BeamLog.warn(
                "UDP liveness: stalled (no datagrams in \(Int(noDatagramTimeoutAfterData))s) → reconnect",
                tag: "viewer"
            )
            disconnectInternal(scheduleReconnect: true)
        }
    }

    // MARK: - Reconnect scheduler

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
        reconnectTimer?.cancel()
        reconnectTimer = nil
    }
}
