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

    // Temporary test switch: auto-accept pairing on Host to prove end-to-end.
    // Set to false to restore manual Accept/Decline.
    public static let autoAcceptDuringTest = true

    // M2: Broadcast plumbing (App Group + cross-process flag)
    public static let appGroup = "group.com.conornolan.beamroom"
    public static let broadcastFlagKey = "br.broadcast.on"
    public static let broadcastDarwinName = "com.conornolan.beamroom.broadcastChanged"

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
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, nil, nil, true)
    }
}
