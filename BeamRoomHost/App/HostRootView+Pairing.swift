//
//  HostRootView+Pairing.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI
import BeamCore

extension HostRootView {
    // MARK: - Pairing card (Step 2 – pinned)

    var pairingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    HostStepChip(number: 2, label: "Pair")

                    Image(systemName: "person.2.wave.2.fill")
                        .imageScale(.large)

                    Text("Pairing")
                        .font(.headline)
                }

                Spacer()

                if model.broadcastOn {
                    HostLiveBadge(text: "Live")
                } else if model.started {
                    HostLiveBadge(text: "Host on")
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
}
