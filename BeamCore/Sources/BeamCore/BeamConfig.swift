//
//  BeamConfig.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//

import Foundation

public enum BeamConfig {
    // Bonjour / service types
    public static let controlService = "_beamctl._tcp"
    public static let mediaService   = "_beamroom._udp"

    // Fixed TCP port for control channel (manual connect / Wi-Fi fallback)
    public static let controlPort: UInt16 = 52345

    // Subsystems for OSLog
    public static let subsystemHost   = "com.conornolan.BeamRoomHost"
    public static let subsystemViewer = "com.conornolan.BeamRoomViewer"
}
