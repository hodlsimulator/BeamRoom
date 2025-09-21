//
//  HostRootView.swift
//  BeamRoomHost
//
//  Created by . . on 9/21/25.
//

import SwiftUI
import BeamCore

struct HostRootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("BeamRoom — Host")
                .font(.largeTitle).bold()
                .multilineTextAlignment(.center)

            Text("M0 scaffold. Ready for discovery and broadcast wiring in M1/M2.")
                .multilineTextAlignment(.center)

            VStack {
                Button("Start (disabled in M0)") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                Button("Go Live (disabled in M0)") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
            }

            Spacer(minLength: 20)

            Text(BeamCore.hello())
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    HostRootView()
}
