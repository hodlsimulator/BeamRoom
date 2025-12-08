//
//  ViewerRootView+BottomBar.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI
import BeamCore

extension ViewerRootView {

    // MARK: Bottom controls (pinned)

    var bottomControlsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                nearbyPairingButton
                Spacer()
                connectionStatus
            }

            if model.showAwareSheet {
                // Inline Wi‑Fi Aware picker instead of a separate sheet.
                awarePickSheet()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            // Match the Share tab pairing card gradient.
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.7),
                                    Color.blue.opacity(0.8),
                                    Color.purple.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.7),
                                    Color.white.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
        )
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 10)
        .animation(.easeInOut(duration: 0.25), value: model.showAwareSheet)
    }

    // MARK: Nearby pairing CTA

    @ViewBuilder
    private var nearbyPairingButton: some View {
        Button {
            // Toggle the inline Wi‑Fi Aware picker.
            model.showAwareSheet.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and-right")
                    .imageScale(.medium)

                Text("Nearby pairing")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Connection status

    @ViewBuilder
    var connectionStatus: some View {
        switch model.client.status {
        case .idle:
            EmptyView()

        case .connecting(let hostName, _):
            Label("Connecting to \(hostName)…", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))

        case .waitingAcceptance:
            Label("Waiting for Host…", systemImage: "hourglass")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))

        case .paired:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.green)

        case .failed:
            Label("Connection failed", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }
}
