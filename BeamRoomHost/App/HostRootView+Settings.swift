//
// HostRootView+Settings.swift
// BeamRoomHost
//
// Created by . . on 12/8/25.

import SwiftUI

extension HostRootView {

    // MARK: - Host settings card

    var hostSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Advanced host settings + current hosting state
            HStack {
                HStack(spacing: 8) {
                    HostStepChip(number: 0, label: "Advanced")

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Host settings")
                            .font(.subheadline.weight(.semibold))

                        // Short hint so this reads as “optional / advanced”
                        Text("Optional controls for how this device hosts Viewers. Most sharing flows work fine without changing anything here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
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

            // Hosting status summary (sessions + broadcast)
            hostStatusSummary

            // Service / device name shown to Viewers
            VStack(alignment: .leading, spacing: 6) {
                Text("Device name for Viewers")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Text("Shown on nearby devices when picking a Host. Defaults to the device name in Settings, but can be customised here.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField("Device name", text: $model.serviceName)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }

            // Advanced: automatically accept pairing without manual tap
            Toggle(
                "Auto-accept pairing",
                isOn: Binding(
                    get: { model.autoAccept },
                    set: { value in
                        model.setAutoAccept(value)
                    }
                )
            )

            // Advanced: turn the host server on/off without touching broadcast
            Button {
                model.toggleServer()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: model.started ? "stop.circle.fill" : "play.circle")
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.started ? "Turn off hosting" : "Turn on hosting")
                            .font(.subheadline.weight(.semibold))

                        Text("Keeps this device visible to nearby Viewers even before the Screen Broadcast is started.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white.opacity(0.18))

            // Low-level diagnostics – kept for DEBUG builds only
            #if DEBUG
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and-right")
                    .imageScale(.small)

                if let peer = model.udpPeer {
                    Text("UDP peer: \(peer)")
                } else {
                    Text("UDP peer: none")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            #endif
        }
        .padding(18)
        .hostGlassCard(cornerRadius: 22)
        .foregroundStyle(.white)
    }

    private var hostStatusSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.started {
                Text(hostStatusLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))

                if model.broadcastOn {
                    Text("Screen Broadcast is on. Connected Viewers currently see the screen.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    Text("Screen Broadcast is off. Connected Viewers will see the screen once broadcasting starts.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                }
            } else {
                Text("Hosting is currently off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Turn hosting on here to let nearby Viewers find this device before starting the Screen Broadcast.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hostStatusLine: String {
        let count = model.sessions.count

        switch count {
        case 0:
            return "Hosting is on. No Viewers connected yet."
        case 1:
            return "Hosting is on. 1 Viewer connected."
        default:
            return "Hosting is on. \(count) Viewers connected."
        }
    }
}
