//
//  BeamRoomViewerApp.swift
//  BeamRoomViewer
//
//  Created by . . on 9/21/25.
//

import SwiftUI
import OSLog
import BeamCore

@main
struct BeamRoomViewerApp: App {
    init() {
        #if AWARE_UI_ENABLED
        Logger(subsystem: "com.conornolan.BeamRoom", category: "build")
            .info("AWARE_UI_ENABLED = ON (Viewer)")
        #else
        Logger(subsystem: "com.conornolan.BeamRoom", category: "build")
            .info("AWARE_UI_ENABLED = OFF (Viewer)")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ViewerRootView()
        }
    }
}
