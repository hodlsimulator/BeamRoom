//
//  ViewerRootView+Idle.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI
import UIKit
import BeamCore

extension ViewerRootView {

    // MARK: - Idle state before any video arrives

    var idleStateView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer(minLength: 24)

                heroCard

                if model.browser.hosts.isEmpty {
                    discoveringView
                } else {
                    primaryConnectButton()

                    if model.browser.hosts.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Other nearby Hosts")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            hostList
                        }
                    }
                }

                if model.showPermHint && model.browser.hosts.isEmpty {
                    permissionHint
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 70) // space above pinned bottom controls
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        StepChip(number: 1, label: "Join")
                    }

                    Text("Join a screen")
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(idleSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(10)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.26),
                                        Color.white.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }

            HStack(spacing: 8) {
                StatusPill(
                    icon: "dot.radiowaves.left.and.right",
                    label: hostsStatusLabel
                )
            }
            .font(.caption2)
        }
        .padding(20)
        .glassCard(cornerRadius: 30)
        .foregroundStyle(.white)
    }

    private var hostsStatusLabel: String {
        let count = model.browser.hosts.count

        switch count {
        case 0:
            return "Searching for Hosts"
        case 1:
            return "1 Host found"
        default:
            return "\(count) Hosts found"
        }
    }

    private var idleSubtitle: String {
        let count = model.browser.hosts.count

        if count == 0 {
            // No Hosts discovered yet – explain the simple flow.
            return "When a device starts sharing from the Share tab, it appears below and BeamRoom connects automatically."
        } else if count == 1 {
            // Single Host – matches the auto‑connect behaviour.
            return "Found 1 nearby Host below.\nBeamRoom will connect automatically."
        } else {
            // Multiple Hosts – user chooses which one to join.
            return "Found \(count) nearby Hosts below.\nChoose one to start watching."
        }
    }

    // MARK: - Host list + discovery

    private var primaryHost: DiscoveredHost? {
        if let selected = model.selectedHost {
            return selected
        }
        return model.browser.hosts.first
    }

    @ViewBuilder
    func primaryConnectButton() -> some View {
        if let host = primaryHost {
            Button {
                model.pick(host)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28, weight: .semibold))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect to")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))

                        Text(host.name)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .glassCard(cornerRadius: 24)
        }
    }

    @ViewBuilder
    var discoveringView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.white)

                Text("Looking for nearby Hosts on this network…")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Text("Once a Host is found, it appears above and BeamRoom connects automatically.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    var hostList: some View {
        VStack(spacing: 8) {
            ForEach(model.browser.hosts) { host in
                Button {
                    model.pick(host)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .imageScale(.medium)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.name)
                                .font(.body)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)

                            Text("Tap to connect")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassCard(cornerRadius: 18)
            }
        }
    }

    @ViewBuilder
    var permissionHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)

            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing showing up?")
                    .font(.footnote.weight(.semibold))

                Text("Local Network access for BeamRoom may need to be enabled in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer(minLength: 6)

            Button("Open") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.18))
            )
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
        .foregroundStyle(.white)
    }
}

// MARK: - Small reusable views for styling

private struct StatusPill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .imageScale(.small)

            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.16))
        )
    }
}

private struct StepChip: View {
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

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.20),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.9),
                                        Color.white.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 8)
            )
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}
