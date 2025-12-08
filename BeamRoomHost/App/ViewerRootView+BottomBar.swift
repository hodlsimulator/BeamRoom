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
        VStack(alignment: .leading, spacing: 12) {

            // Header: Step 2 – Pair, mirroring the Host pairing card language.
            HStack {
                HStack(spacing: 8) {
                    ViewerStepChip(number: 2, label: "Pair")

                    Image(systemName: "person.2.wave.2.fill")
                        .imageScale(.medium)

                    Text("Nearby pairing")
                        .font(.subheadline.weight(.semibold))
                }

                Spacer()

                connectionStatus
            }

            // Main Nearby pairing CTA
            HStack {
                nearbyPairingButton
                Spacer()
            }

            // Inline Wi‑Fi Aware picker instead of a separate sheet.
            if model.showAwareSheet {
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

                Text("Start nearby pairing")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.20))
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

// MARK: - Small reusable view for step chip (Viewer)

private struct ViewerStepChip: View {
    let number: Int
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text("\(number)")
                .font(.caption2.weight(.semibold))
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.9))
                )
                .foregroundColor(Color.accentColor)

            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.12))
        )
    }
}
