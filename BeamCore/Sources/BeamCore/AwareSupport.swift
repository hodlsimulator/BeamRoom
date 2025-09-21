//
//  AwareSupport.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//

//
//  AwareSupport.swift
//  BeamCore
//

import Foundation
import OSLog

#if canImport(WiFiAware)
import WiFiAware
#endif

public enum AwareDiag {
    public static func logOnce(role: String) {
        #if canImport(WiFiAware)
        if #available(iOS 26.0, *) {
            let ok = WACapabilities.supportedFeatures.contains(.wifiAware)
            Logger(subsystem: "com.conornolan.BeamRoom", category: "aware")
                .info("Aware[\(role, privacy: .public)] supported=\(ok)")
        }
        #endif
    }
}
