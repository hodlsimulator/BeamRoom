//
//  BeamConcurrencyShims.swift
//  BeamCore
//
//  Created by . . on 9/22/25.
//

import Foundation

// These classes are used across @Sendable closures (NWBrowser/NWListener/NWConnection handlers).
// Mark them @unchecked Sendable to silence strict-concurrency capture errors. We already hop
// to the main actor before touching UI state, so this is safe for our usage.
extension BeamBrowser: @unchecked Sendable {}
extension BeamControlClient: @unchecked Sendable {}
extension BeamControlServer: @unchecked Sendable {}
