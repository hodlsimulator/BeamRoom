//
//  UDPMediaClient.swift
//  BeamCore
//
//  Created by . . on 9/27/25.
//
// Viewer-side UDP media receiver + tiny test-frame decoder (BGRA32)
//

import Foundation
import Combine
import Network
import OSLog
import CoreGraphics

private let mediaLog = Logger(subsystem: BeamConfig.subsystemViewer, category: "udp-media")

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
    private var windowStart = Date()
    private var lastFrameTS = Date()
    private var connectedKey: String?

    public init() {}

    public func connect(toHost host: NWEndpoint.Host, port: UInt16) {
        // De-dupe if already connected to same target
        let key = "\(host):\(port)"
        if connectedKey == key { return }
        disconnect()
        connectedKey = key

        let params = NWParameters.udp
        params.requiredInterfaceType = .wifi
        params.includePeerToPeer = false

        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let c = NWConnection(host: host, port: nwPort, using: params)
        conn = c

        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                mediaLog.info("UDP ready → \(String(describing: host)):\(port)")
                Task { @MainActor in
                    self.sendHello()
                    self.receiveLoop()
                }
            case .failed(let err):
                mediaLog.error("UDP failed: \(err.localizedDescription)")
                Task { @MainActor in self.disconnect() }
            case .cancelled:
                mediaLog.notice("UDP cancelled")
                Task { @MainActor in self.disconnect() }
            default: break
            }
        }
        c.start(queue: .main)
    }

    public func disconnect() {
        conn?.cancel()
        conn = nil
        lastImage = nil
        stats = .init()
        bytesInWindow = 0
        connectedKey = nil
    }

    // MARK: - IO

    private func sendHello() {
        guard let c = conn else { return }
        let hello = Data([0x42, 0x52, 0x48, 0x49, 0x21]) // "BRHI!"
        c.send(content: hello, completion: .contentProcessed { _ in
            mediaLog.debug("UDP hello → sent")
        })
    }

    private func receiveLoop() {
        guard let c = conn else { return }
        c.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let d = data, !d.isEmpty {
                self.handleDatagram(d)
            }
            if let error {
                mediaLog.error("UDP recv error: \(error.localizedDescription)")
                Task { @MainActor in self.disconnect() }
                return
            }
            self.receiveLoop()
        }
    }

    private func handleDatagram(_ data: Data) {
        // Header: [u32 magic 'BMRM'][u32 seq][u16 w][u16 h] (all big-endian)
        guard data.count >= 12 else { return }
        let magic = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).bigEndian }
        guard magic == 0x424D524D else { return } // 'BMRM'
        let seq   = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self).bigEndian }
        let w     = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt16.self).bigEndian })
        let h     = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 10, as: UInt16.self).bigEndian })
        let pixelBytes = data.count - 12
        guard pixelBytes == w * h * 4 else { return }

        // Stats
        if stats.frames > 0, seq > stats.lastSeq + 1 {
            stats.drops += UInt64(seq - stats.lastSeq - 1)
        }
        stats.lastSeq = seq
        stats.frames += 1
        bytesInWindow += data.count
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 1.0 {
            let seconds = now.timeIntervalSince(windowStart)
            // Compute over the last 1s window
            stats.fps = Double(bytesInWindow == 0 ? 0 : Int(Double(stats.frames) * (1.0 / seconds))) // best-effort
            stats.kbps = Double(bytesInWindow * 8) / seconds / 1000.0
            windowStart = now
            bytesInWindow = 0
        }
        lastFrameTS = now

        // Image (BGRA32, premultipliedFirst, byteOrder32Little)
        let pixels = data.subdata(in: 12..<data.count) as CFData
        guard let provider = CGDataProvider(data: pixels) else { return }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue |
            CGBitmapInfo.byteOrder32Little.rawValue
        )
        guard let cg = CGImage(
            width: w, height: h,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: cs, bitmapInfo: info,
            provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent
        ) else { return }

        lastImage = cg
    }
}
