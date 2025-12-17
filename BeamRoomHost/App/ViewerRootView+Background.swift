//
//  ViewerRootView+Background.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI
import UIKit

extension ViewerRootView {
    // MARK: Background

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

            // Cool blue glow behind the hero card.
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
                .offset(x: -40, y: -90)

            // Warm complementary glow near the bottom controls.
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
                .offset(x: 80, y: 140)

            // Soft diagonal streak.
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

    // MARK: Active video mode with a minimal control overlay.

    @ViewBuilder
    func videoView(_ cgImage: CGImage) -> some View {
        Image(uiImage: UIImage(cgImage: cgImage))
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .background(Color.black)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button {
                    model.cancelPairing()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .frame(width: 44, height: 44)
                }
                .contentShape(Rectangle())
                .background(.thinMaterial)
                .clipShape(Circle())
                .padding(.top, 16)
                .padding(.trailing, 16)
                .accessibilityLabel("Stop viewing")
            }
    }
}
