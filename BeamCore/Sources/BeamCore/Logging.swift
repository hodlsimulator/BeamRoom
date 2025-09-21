//
//  Logging.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//

#if canImport(OSLog)
import OSLog

// iOS 14+ (we’re on iOS 26, so fine)
public enum BeamLog {
    private static let core = Logger(subsystem: "com.conornolan.BeamRoom", category: "core")
    public static func info(_ message: String)  { core.info("\(message, privacy: .public)") }
    public static func error(_ message: String) { core.error("\(message, privacy: .public)") }
    public static func debug(_ message: String) { core.debug("\(message, privacy: .public)") }
}
#else
// Fallback used if the indexer ever builds the package for an unsupported platform
public enum BeamLog {
    public static func info(_ message: String)  { print("[INFO]  \(message)") }
    public static func error(_ message: String) { print("[ERROR] \(message)") }
    public static func debug(_ message: String) { print("[DEBUG] \(message)") }
}
#endif
