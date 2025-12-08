//
//  HostRootView+Layout.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI
import BeamCore

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

    // MARK: - Main hero card (Step 1)

    var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        StepChip(number: 1, label: "Go live")

                        if model.broadcastOn {
                            LiveBadge(text: "Live")
                        } else if model.started {
                            LiveBadge(text: "Ready")
                        }
                    }

                    Text(heroTitle)
                        .font(.title2.weight(.semibold))

                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Image(systemName: "rectangle.on.rectangle.badge.person.crop")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.9),
                                Color.white.opacity(0.4)
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
                                        Color.white.opacity(0.24),
                                        Color.white.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blur(radius: 0.5)
                    )
            }

            Button {
                startQuickShare()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.broadcastOn ? "dot.radiowaves.left.and.right" : "play.fill")
                        .imageScale(.large)

                    Text(model.broadcastOn ? "Manage broadcast" : "Start sharing")
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .foregroundColor(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color.white.opacity(0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(
                            color: Color.accentColor.opacity(0.45),
                            radius: 22,
                            x: 0,
                            y: 10
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                model.broadcastOn
                    ? "Open Screen Broadcast controls"
                    : "Start hosting and open Screen Broadcast sheet"
            )

            statusPills

            if !model.broadcastOn {
                Button {
                    showingBroadcastHelp = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                            .imageScale(.small)

                        Text("Problems starting the broadcast?")
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }

            // Hidden system picker – the large button taps this internally.
            BroadcastPickerShim(controller: broadcastController)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
        }
        .padding(20)
        .glassCard(cornerRadius: 30)
        .foregroundStyle(.white)
    }

    private var heroTitle: String {
        if model.broadcastOn {
            return "Streaming to Viewers"
        } else if model.started {
            return "Hosting is ready"
        } else {
            return "Share this screen"
        }
    }

    private var heroSubtitle: String {
        if model.broadcastOn {
            return "Everything on the screen is mirrored to connected devices."
        } else if model.started {
            return "Start the Screen Broadcast when ready to go live."
        } else {
            return "Start hosting and open the Screen Broadcast sheet in one tap."
        }
    }

    // MARK: - Host settings card

    var hostSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    StepChip(number: 0, label: "Optional")

                    Text("Host settings")
                        .font(.subheadline.weight(.semibold))
                }

                Spacer()

                Label(
                    model.started ? "Hosting on" : "Not hosting",
                    systemImage: model.started ? "wifi.router.fill" : "wifi.slash"
                )
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Service name")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Service name", text: $model.serviceName)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }

            Toggle(
                "Auto-accept pairing",
                isOn: Binding(
                    get: { model.autoAccept },
                    set: { model.setAutoAccept($0) }
                )
            )

            Button {
                model.toggleServer()
            } label: {
                Label {
                    Text(model.started ? "Stop hosting only" : "Start hosting only")
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                } icon: {
                    Image(systemName: model.started ? "stop.circle.fill" : "play.circle")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white.opacity(0.18))

            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .imageScale(.small)

                if let peer = model.udpPeer {
                    Text("UDP peer: \(peer)")
                } else {
                    Text("UDP peer: none")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
        .foregroundStyle(.white)
    }

    // MARK: - Pairing card (Step 2 – pinned)

    var pairingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    StepChip(number: 2, label: "Pair")

                    Image(systemName: "person.2.wave.2.fill")
                        .imageScale(.large)

                    Text("Pairing")
                        .font(.headline)
                }

                Spacer()

                if model.broadcastOn {
                    LiveBadge(text: "Live")
                } else if model.started {
                    LiveBadge(text: "Host on")
                }
            }

            if model.pendingPairs.isEmpty && model.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Waiting for Viewers to pair…")
                        .font(.subheadline.weight(.medium))

                    Text("Ask the Viewer to open BeamRoom on another device and choose Watch.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            ForEach(model.pendingPairs) { pending in
                VStack(alignment: .leading, spacing: 10) {
                    Text(pending.remoteDescription)
                        .font(.subheadline.weight(.semibold))

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("Pair code")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))

                        Text(pending.code)
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                    }

                    HStack(spacing: 12) {
                        Button(role: .cancel) {
                            model.decline(pending.id)
                        } label: {
                            Text("Decline")
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            Color.white.opacity(0.6),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.accept(pending.id)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark")
                                Text("Pair viewer")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.9)
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white,
                                                Color.white.opacity(0.96)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .foregroundColor(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Accept pairing with \(pending.remoteDescription)")
                    }
                }
            }

            if !model.sessions.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.3))

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.sessions) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.remoteDescription)

                                Text(
                                    "Connected \(session.startedAt.formatted(date: .omitted, time: .shortened))"
                                )
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .imageScale(.large)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
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
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
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
    }

    // MARK: - Helper labels

    private var viewerCountLabel: String {
        let count = model.sessions.count

        switch count {
        case 0:
            return "No viewers"
        case 1:
            return "1 viewer"
        default:
            return "\(count) viewers"
        }
    }

    private var statusPills: some View {
        HStack(spacing: 8) {
            StatusPill(
                icon: model.started ? "wifi.router.fill" : "wifi.slash",
                label: model.started ? "Hosting on" : "Not hosting"
            )

            StatusPill(
                icon: "person.2.fill",
                label: viewerCountLabel
            )

            StatusPill(
                icon: model.broadcastOn ? "dot.radiowaves.left.right" : "wave.3.right",
                label: model.broadcastOn ? "Broadcast on" : "Broadcast off"
            )
        }
        .font(.caption2)
    }

    /// Ensures the server is running, then taps the hidden Broadcast picker.
    private func startQuickShare() {
        if !model.started {
            model.toggleServer()
        }

        broadcastController.startBroadcast()
    }
}

// MARK: - Small reusable views

private struct StatusPill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .imageScale(.small)

            Text(label)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.14))
        )
    }
}

private struct LiveBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                )

            Text(text.uppercased())
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.18))
        )
        .foregroundStyle(.white)
    }
}

private struct StepChip: View {
    let number: Int
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            if number > 0 {
                Text("\(number)")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.9))
                    )
                    .foregroundColor(Color.accentColor)
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 16, height: 16)
                    .foregroundColor(Color.white.opacity(0.85))
            }

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
