//
//  HostRootView+Hero.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI

extension HostRootView {
    // MARK: - Main hero card (Step 1)

    var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        HostStepChip(number: 1, label: "Go live")

                        if model.broadcastOn {
                            HostLiveBadge(text: "Live")
                        } else if model.started {
                            HostLiveBadge(text: "Ready")
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
                    Image(
                        systemName: model.broadcastOn
                            ? "dot.radiowaves.left.and.right"
                            : "play.fill"
                    )
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
        .hostGlassCard(cornerRadius: 30)
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
            HostStatusPill(
                icon: model.started ? "wifi.router.fill" : "wifi.slash",
                label: model.started ? "Hosting on" : "Not hosting"
            )

            HostStatusPill(
                icon: "person.2.fill",
                label: viewerCountLabel
            )

            HostStatusPill(
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
