//
//  AwareSupport.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//

import Foundation
import OSLog

#if canImport(WiFiAware)
import WiFiAware
#endif

public enum AwareServices {
    // We’ll use the same service strings you already declared in Info.plists.
    public static let control = "_beamctl._tcp"
    public static let media   = "_beamroom._udp"
}

public enum AwareDiag {
    public static func logOnce(role: String) {
        #if canImport(WiFiAware)
        if #available(iOS 26.0, *) {
            let supported = WACapabilities.supportedFeatures.contains(.wifiAware)
            let pubKeys = Array(WAPublishableService.allServices.keys).joined(separator: ",")
            let subKeys = Array(WASubscribableService.allServices.keys).joined(separator: ",")
            Logger(subsystem: "com.conornolan.BeamRoom", category: "aware")
                .info("Aware[\(role, privacy: .public)] supported=\(supported) pub=\(pubKeys, privacy: .public) sub=\(subKeys, privacy: .public)")
        } else {
            Logger(subsystem: "com.conornolan.BeamRoom", category: "aware")
                .info("Aware[\(role, privacy: .public)] iOS<26 (not available)")
        }
        #else
        Logger(subsystem: "com.conornolan.BeamRoom", category: "aware")
            .info("Aware[\(role, privacy: .public)] WiFiAware framework not present")
        #endif
    }
}
