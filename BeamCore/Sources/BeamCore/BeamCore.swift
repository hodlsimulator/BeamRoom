// The Swift Programming Language
// https://docs.swift.org/swift-book

//
//  BeamCore.swift
//  BeamCore
//

import Foundation

public enum BeamCore {
    /// Used by the Host/Viewer UIs as a quick sanity string.
    public static func hello() -> String {
        "BeamCore \(BeamVersion.string)"
    }
}

/// Lightweight version helper with no reliance on `Bundle.module`.
/// Reads the main app’s Info.plist first; falls back to the bundle that contains this type.
enum BeamVersion {
    static let string: String = {
        if let s = versionString(from: .main) { return s }
        if let s = versionString(from: bundleForThisType()) { return s }
        return "v0.0 (dev)"
    }()

    private static func versionString(from bundle: Bundle) -> String? {
        guard let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        return build.isEmpty ? "v\(short)" : "v\(short) (\(build))"
    }

    private static func bundleForThisType() -> Bundle {
        // Use an ObjC-derived token so Bundle(for:) always resolves to the containing binary
        class Token: NSObject {}
        return Bundle(for: Token.self)
    }
}
