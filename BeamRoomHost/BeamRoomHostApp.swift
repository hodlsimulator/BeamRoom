//
//  BeamRoomHostApp.swift
//  BeamRoomHost
//
//  Created by . . on 9/21/25.
//

import SwiftUI
import BeamCore

@main
struct BeamRoomHostApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BeamLog.info("BeamRoomHost launched")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            BeamLog.debug("Scene phase changed: \(String(describing: oldPhase)) → \(String(describing: newPhase))")
        }
    }
}
