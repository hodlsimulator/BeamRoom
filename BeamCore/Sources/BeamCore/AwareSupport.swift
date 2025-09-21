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
import WiFiAware

public enum AwareSupport {
    /// Quick capability check (helps with diagnostics/UI messaging).
    public static var isAvailable: Bool {
        WACapabilities.supportedFeatures.contains(.wifiAware)
    }

    /// Returns true iff Info.plist contains a *dictionary* entry for the given Wi-Fi Aware service.
    /// This preflight avoids the framework assertion when the shape is wrong.
    public static func hasValidAwareConfig(for service: String) -> Bool {
        guard let dict = Bundle.main.object(forInfoDictionaryKey: "WiFiAwareServices") as? [String: Any],
              let _ = dict[service] as? [String: Any] else {
            return false
        }
        return true
    }

    /// Convenience accessor for Viewer (subscriber) services. Returns nil if the plist is not valid.
    public static func subscriberService(named service: String) -> WASubscribableService? {
        guard hasValidAwareConfig(for: service) else { return nil }
        return WASubscribableService.allServices[service]
    }

    /// Convenience accessor for Host (publishable) services. Returns nil if the plist is not valid.
    public static func publishableService(named service: String) -> WAPublishableService? {
        guard hasValidAwareConfig(for: service) else { return nil }
        return WAPublishableService.allServices[service]
    }

    /// One-line diagnostic you can sprinkle into lifecycle points if needed.
    public static func logDiag(role: String, logger: Logger = Logger(subsystem: "com.conornolan.BeamRoom", category: "aware")) {
        logger.info("Aware[\(role, privacy: .public)] available=\(self.isAvailable)")
    }
}
