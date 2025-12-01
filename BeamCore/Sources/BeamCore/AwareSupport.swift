//
//  AwareSupport.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//

import Foundation
import OSLog
import WiFiAware

public enum AwareSupport {
    /// Quick capability check (helps with diagnostics/UI messaging).
    public static var isAvailable: Bool {
        WACapabilities.supportedFeatures.contains(.wifiAware)
    }

    /// Raw WiFiAwareServices dictionary from Info.plist, if present.
    private static var servicesPlist: [String: Any] {
        (Bundle.main.object(forInfoDictionaryKey: "WiFiAwareServices") as? [String: Any]) ?? [:]
    }

    /// Returns the per-service configuration dictionary for the given Wi-Fi Aware service.
    private static func config(for service: String) -> [String: Any]? {
        servicesPlist[service] as? [String: Any]
    }

    /// Returns `true` iff the Info.plist entry for the service includes a `Subscribable` key.
    /// This prevents calling WASubscribableService on a purely publishable service, which
    /// would trigger a framework assertion when parsing the configuration.
    private static func hasSubscribableConfig(for service: String) -> Bool {
        guard let cfg = config(for: service) else { return false }
        return cfg["Subscribable"] != nil
    }

    /// Returns `true` iff the Info.plist entry for the service includes a `Publishable` key.
    private static func hasPublishableConfig(for service: String) -> Bool {
        guard let cfg = config(for: service) else { return false }
        return cfg["Publishable"] != nil
    }

    /// Convenience accessor for Viewer (subscriber) services.
    /// Returns nil if the plist is not valid for subscription.
    public static func subscriberService(named service: String) -> WASubscribableService? {
        guard hasSubscribableConfig(for: service) else { return nil }
        return WASubscribableService.allServices[service]
    }

    /// Convenience accessor for Host (publishable) services.
    /// Returns nil if the plist is not valid for publishing.
    public static func publishableService(named service: String) -> WAPublishableService? {
        guard hasPublishableConfig(for: service) else { return nil }
        return WAPublishableService.allServices[service]
    }

    /// One-line diagnostic you can sprinkle into lifecycle points if needed.
    public static func logDiag(
        role: String,
        logger: Logger = Logger(subsystem: "com.conornolan.BeamRoom", category: "aware")
    ) {
        logger.info("Aware[\(role, privacy: .public)] available=\(self.isAvailable)")
    }
}
