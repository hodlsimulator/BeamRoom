//
//  UDPMediaSender.swift
//  BeamRoomHost
//
//  Created by . . on 9/27/25.
//
//  Broadcast Upload extension: UDP sender that targets the active Viewer peer from App Group.
//

import Foundation
import Network
import OSLog
import BeamCore

final class UDPMediaSender: @unchecked Sendable {
    private let log = Logger(subsystem: BeamConfig.subsystemExt, category: "udp-sender")
    private var conn: NWConnection?
    private var currentKey: String?

    init() {
        // Observe media peer changes
        let name = CFNotificationName(BeamConfig.mediaPeerDarwinName as CFString)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            { _, observer, _, _, _ in
                let me = Unmanaged<UDPMediaSender>.fromOpaque(observer!).takeUnretainedValue()
                me.reconnectIfNeeded()
            },
            name.rawValue,
            nil,
            .deliverImmediately
        )
        reconnectIfNeeded()
    }

    deinit {
        conn?.cancel(); conn = nil
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }

    func reconnectIfNeeded() {
        guard let peer = BeamConfig.getMediaPeer() else {
            if conn != nil { log.notice("No media peer → closing") }
            conn?.cancel(); conn = nil; currentKey = nil
            return
        }
        let key = "\(peer.host):\(peer.port)"
        if currentKey == key { return }
        currentKey = key
        conn?.cancel(); conn = nil
        guard let port = NWEndpoint.Port(rawValue: peer.port) else { return }
        let c = NWConnection(host: NWEndpoint.Host(peer.host), port: port, using: .udp)
        let logger = self.log

        c.stateUpdateHandler = { st in
            switch st {
            case .ready:
                logger.info("UDP ready to \(peer.host):\(peer.port)")
                // Send a tiny hello so Host logs the first packet (optional)
                c.send(content: Data([0x42,0x52,0x48,0x49,0x21]), completion: .contentProcessed { _ in })
            case .failed(let e): logger.error("UDP failed: \(e.localizedDescription, privacy: .public)")
            case .waiting(let e): logger.notice("UDP waiting: \(e.localizedDescription, privacy: .public)")
            default: break
            }
        }
        c.start(queue: .main)
        conn = c
    }

    func send(_ datagrams: [Data]) {
        guard let c = conn else { return }
        let logger = self.log
        for d in datagrams {
            c.send(content: d, completion: .contentProcessed { err in
                if let e = err { logger.error("UDP send error: \(e.localizedDescription, privacy: .public)") }
            })
        }
    }
}
