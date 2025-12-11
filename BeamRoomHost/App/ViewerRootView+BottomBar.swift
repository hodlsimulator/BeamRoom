//
//  ViewerRootView+BottomBar.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI
import BeamCore

extension ViewerRootView {

    // MARK: - Bottom controls (pinned)

    var bottomControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Step 2 – Pair.
            HStack {
                HStack(spacing: 8) {
                    ViewerStepChip(number: 2, label: "Pair")

                    Image(systemName: "person.2.wave.2.fill")
                        .imageScale(.medium)

                    Text("Nearby pairing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }

                Spacer()

                connectionStatus
            }

            Text(nearbySubtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            if shouldShowNearbyCTA {
                nearbyPairingButton
            }

            // Inline Wi‑Fi Aware picker instead of a separate sheet.
            if model.showAwareSheet {
                awarePickSheet()
                    .transition(
                        .opacity
                        .combined(with: .move(edge: .bottom))
                    )
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

    private var nearbySubtitle: String {
        switch model.client.status {
        case .failed:
            return "Automatic discovery did not work. Start nearby pairing to connect directly to the Host device."
        case .paired:
            return "Connected. Nearby pairing stays ready in case the Host moves to a different network."
        default:
            if model.browser.hosts.isEmpty {
                return "Start nearby pairing on both devices if the Host is not appearing above."
            } else {
                return "If connecting to the Host above does not work, try nearby pairing instead."
            }
        }
    }

    /// Whether to show the Nearby pairing CTA button.
    private var shouldShowNearbyCTA: Bool {
        // Hide the CTA only once we are fully paired.
        if case .paired = model.client.status {
            return false
        }
        return true
    }

    private var canStartNearbyPairing: Bool {
        switch model.client.status {
        case .idle, .failed:
            return true
        default:
            return false
        }
    }

    // MARK: - Nearby pairing CTA

    @ViewBuilder
    private var nearbyPairingButton: some View {
        Button {
            if canStartNearbyPairing {
                // Toggle the inline Wi‑Fi Aware picker.
                model.showAwareSheet.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and-right")
                    .imageScale(.medium)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Start nearby pairing")
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)

                    Text("Looks for a Host right next to this device.")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor,
                                Color.blue.opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .foregroundColor(.white)
            .shadow(
                color: Color.black.opacity(0.35),
                radius: 18,
                x: 0,
                y: 8
            )
        }
        .buttonStyle(.plain)
        .disabled(!canStartNearbyPairing)
        .opacity(canStartNearbyPairing ? 1.0 : 0.6)
        .accessibilityLabel("Start nearby pairing")
    }

    // MARK: - Connection status

    @ViewBuilder
    var connectionStatus: some View {
        switch model.client.status {
        case .idle:
            EmptyView()

        case .connecting(let hostName, _):
            Label("Connecting to \(hostName)…", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

        case .waitingAcceptance:
            Label("Waiting for Host…", systemImage: "hourglass")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

        case .paired:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.green)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

        case .failed:
            Label("Connection failed", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.12))
        )
    }
}
