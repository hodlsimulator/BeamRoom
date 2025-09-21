//
//  BeamConfig.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//

import Foundation

public enum BeamConfig {
    // Bonjour / service types
    public static let mediaService: String   = "_beamroom._udp"
    public static let controlService: String = "_beamctl._tcp"

    // Fixed TCP control port
    public static let controlPort: UInt16 = 52345

    // OSLog subsystems (one per target)
    public static let subsystemHost   = "com.conornolan.BeamRoomHost"
    public static let subsystemViewer = "com.conornolan.BeamRoomViewer"
    public static let subsystemExt    = "com.conornolan.BeamRoomBroadcastUpload"

    // Temporary test switch: auto-accept pairing on Host to prove end-to-end.
    // Set to false to restore manual Accept/Decline.
    public static let autoAcceptDuringTest = true
}
