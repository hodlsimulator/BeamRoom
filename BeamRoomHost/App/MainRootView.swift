//
//  MainRootView.swift
//  BeamRoomHost
//
//  Created by . . on 12/1/25.
//

import SwiftUI

enum BeamMode: String, CaseIterable, Identifiable {
    case share
    case watch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .share: return "Share"
        case .watch: return "Watch"
        }
    }

    var systemImage: String {
        switch self {
        case .share: return "rectangle.on.rectangle"
        case .watch: return "eye"
        }
    }
}

struct MainRootView: View {
    @AppStorage("beamroom.selectedMode")
    private var selectedMode: BeamMode = .share

    var body: some View {
        TabView(selection: $selectedMode) {
            HostRootView()
                .tabItem {
                    Label(BeamMode.share.label, systemImage: BeamMode.share.systemImage)
                }
                .tag(BeamMode.share)

            ViewerRootView()
                .tabItem {
                    Label(BeamMode.watch.label, systemImage: BeamMode.watch.systemImage)
                }
                .tag(BeamMode.watch)
        }
    }
}
