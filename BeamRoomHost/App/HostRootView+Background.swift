//
//  HostRootView+Background.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI

extension HostRootView {
    // MARK: - Background

    var liquidBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.12),
                    Color(red: 0.01, green: 0.01, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Cool blue glow behind hero card
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.accentColor.opacity(0.6),
                            Color.accentColor.opacity(0.0)
                        ],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .blur(radius: 40)
                .offset(x: -40, y: -80)

            // Warm complementary glow near pairing area
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.orange.opacity(0.45),
                            Color.orange.opacity(0.0)
                        ],
                        center: .bottomTrailing,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .blur(radius: 50)
                .offset(x: 80, y: 120)

            // Soft diagonal streak
            RoundedRectangle(cornerRadius: 200, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .rotationEffect(.degrees(-18))
                .blur(radius: 60)
                .offset(x: 40, y: 40)
        }
        .ignoresSafeArea()
    }
}
