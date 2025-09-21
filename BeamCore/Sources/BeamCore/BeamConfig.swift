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

    // OSLog subsystems
    public static let subsystemHost   = "com.conornolan.BeamRoomHost"
    public static let subsystemViewer = "com.conornolan.BeamRoomViewer"

    // ✅ Temporary: auto-accept incoming pairing on Host to prove the path end-to-end.
    // Turn this off when you want manual Accept/Decline again.
    public static let autoAcceptDuringTest = true
}
