//
//  BeamConfig.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//

import Foundation

public enum BeamConfig {
    public static let appGroup = "group.com.conornolan.beamroom"
    public static let mediaService = "_beamroom._udp"
    public static let controlService = "_beamctl._tcp"

    public static let subsystemBase = "com.conornolan.BeamRoom"
    public static let subsystemHost = "\(subsystemBase).host"
    public static let subsystemViewer = "\(subsystemBase).viewer"
    public static let subsystemExt = "\(subsystemBase).ext"
}
