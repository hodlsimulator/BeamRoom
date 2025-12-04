//
//  BeamConfig.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//

import Foundation
import CoreFoundation

public enum BeamConfig {
    // Bonjour / service types
    public static let mediaService: String = "_beamroom._udp"
    public static let controlService: String = "_beamctl._tcp"

    // Fixed TCP control port
    public static let controlPort: UInt16 = 52345

    // OSLog subsystems (one per target)
    public static let subsystemHost = "com.conornolan.BeamRoomHost"
    public static let subsystemViewer = "com.conornolan.BeamRoomViewer"
    public static let subsystemExt = "com.conornolan.BeamRoomBroadcastUpload"

    // TEST SWITCH: auto-accept pairing on Host.
    // Enabled only for DEBUG builds so shipping builds default to manual accept.
    #if DEBUG
    public static let autoAcceptDuringTest = true
    #else
    public static let autoAcceptDuringTest = false
    #endif

    // M2: Broadcast plumbing (App Group + cross-process flag)
    public static let appGroup = "group.com.conornolan.beamroom"
    public static let broadcastFlagKey = "br.broadcast.on"
    public static let broadcastDarwinName = "com.conornolan.beamroom.broadcastChanged"

    // M3: UDP port (host’s media sender/listener port)
    public static let broadcastUDPPortKey = "br.broadcast.udpPort"

    // M4: Active media peer (Viewer’s remote UDP endpoint as seen by Host)
    public static let mediaPeerHostKey = "br.media.peer.host"
    public static let mediaPeerPortKey = "br.media.peer.port"
    public static let mediaPeerDarwinName = "com.conornolan.beamroom.mediaPeerChanged"

    @inline(__always)
    public static func isBroadcastOn() -> Bool {
        UserDefaults(suiteName: appGroup)?.bool(forKey: broadcastFlagKey) ?? false
    }

    @inline(__always)
    public static func setBroadcast(on: Bool) {
        guard let d = UserDefaults(suiteName: appGroup) else { return }
        d.set(on, forKey: broadcastFlagKey)
        d.synchronize()

        let name = CFNotificationName(broadcastDarwinName as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name,
            nil,
            nil,
            true
        )
    }

    @inline(__always)
    public static func getBroadcastUDPPort() -> UInt16? {
        guard let d = UserDefaults(suiteName: appGroup) else { return nil }
        let n = d.integer(forKey: broadcastUDPPortKey)
        return (n > 0 && n <= Int(UInt16.max)) ? UInt16(n) : nil
    }

    @inline(__always)
    public static func setBroadcastUDPPort(_ port: UInt16?) {
        guard let d = UserDefaults(suiteName: appGroup) else { return }
        if let p = port {
            d.set(Int(p), forKey: broadcastUDPPortKey)
        } else {
            d.removeObject(forKey: broadcastUDPPortKey)
        }
        d.synchronize()
    }

    // MARK: - M4 media peer (Host → Extension)

    @inline(__always)
    public static func setMediaPeer(host: String?, port: UInt16?) {
        guard let d = UserDefaults(suiteName: appGroup) else { return }

        if let host, let port {
            d.set(host, forKey: mediaPeerHostKey)
            d.set(Int(port), forKey: mediaPeerPortKey)
        } else {
            d.removeObject(forKey: mediaPeerHostKey)
            d.removeObject(forKey: mediaPeerPortKey)
        }

        d.synchronize()

        let name = CFNotificationName(mediaPeerDarwinName as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name,
            nil,
            nil,
            true
        )
    }

    @inline(__always)
    public static func getMediaPeer() -> (host: String, port: UInt16)? {
        guard
            let d = UserDefaults(suiteName: appGroup),
            let host = d.string(forKey: mediaPeerHostKey)
        else {
            return nil
        }

        let p = d.integer(forKey: mediaPeerPortKey)
        guard p > 0 && p <= Int(UInt16.max) else {
            return nil
        }

        return (host, UInt16(p))
    }
}
