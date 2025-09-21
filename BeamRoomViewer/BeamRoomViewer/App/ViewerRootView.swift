//
//  ViewerRootView.swift
//  BeamRoomViewer
//
//  Created by . . on 9/21/25.
//

import SwiftUI
import BeamCore

struct ViewerRootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("BeamRoom — Viewer")
                .font(.largeTitle).bold()
                .multilineTextAlignment(.center)

            Text("M0 scaffold. Discovery and playback arrive in M1–M4.")
                .multilineTextAlignment(.center)

            Spacer(minLength: 12)

            Text(BeamCore.hello())
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview { ViewerRootView() }
