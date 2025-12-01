//
//  BeamRoomHostApp.swift
//  BeamRoomHost
//
//  Created by . . on 9/21/25.
//

import SwiftUI
import OSLog
import BeamCore

@main
struct BeamRoomHostApp: App {
    init() {
        #if AWARE_UI_ENABLED
        Logger(subsystem: "com.conornolan.BeamRoom", category: "build")
            .info("AWARE_UI_ENABLED = ON (Unified)")
        #else
        Logger(subsystem: "com.conornolan.BeamRoom", category: "build")
            .info("AWARE_UI_ENABLED = OFF (Unified)")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainRootView()
        }
    }
}
