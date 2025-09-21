//
//  Logging.swift
//  BeamCore
//
//  Created by . . on 9/21/25.
//

//
//  Logging.swift
//  BeamCore
//

import Foundation
import OSLog

public enum BeamLogLevel: String, Codable, Sendable {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"
}

public struct BeamLogEntry: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let ts: Date
    public let level: BeamLogLevel
    public let tag: String
    public let message: String

    public init(ts: Date = Date(), level: BeamLogLevel, tag: String, message: String) {
        self.id = UUID()
        self.ts = ts
        self.level = level
        self.tag = tag
        self.message = message
    }
}

@MainActor
public final class BeamInAppLog: ObservableObject {
    public static let shared = BeamInAppLog()
    @Published public private(set) var entries: [BeamLogEntry] = []
    public var maxEntries: Int = 4000

    private init() {}

    public func clear() { entries.removeAll() }

    public func append(level: BeamLogLevel, tag: String, _ message: String) {
        entries.append(BeamLogEntry(level: level, tag: tag, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func dumpText() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_GB")
        df.dateFormat = "HH:mm:ss.SSS"
        return entries.map { e in
            "[\(df.string(from: e.ts))][\(e.level.rawValue)][\(e.tag)] \(e.message)"
        }.joined(separator: "\n")
    }
}

public enum BeamLog {
    static let core = Logger(subsystem: "com.conornolan.BeamRoom", category: "core")

    private static func append(_ level: BeamLogLevel, tag: String, _ message: String) {
        Task { @MainActor in
            BeamInAppLog.shared.append(level: level, tag: tag, message)
        }
    }

    public static func debug(_ message: String, tag: String = "app") {
        core.debug("\(message, privacy: .public)")
        append(.debug, tag: tag, message)
    }

    public static func info(_ message: String, tag: String = "app") {
        core.info("\(message, privacy: .public)")
        append(.info, tag: tag, message)
    }

    public static func warn(_ message: String, tag: String = "app") {
        core.notice("\(message, privacy: .public)")
        append(.warn, tag: tag, message)
    }

    public static func error(_ message: String, tag: String = "app") {
        core.error("\(message, privacy: .public)")
        append(.error, tag: tag, message)
    }
}
