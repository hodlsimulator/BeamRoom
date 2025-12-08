//
//  HostRootView+Settings.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

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

            // Service / device name shown to Viewers
            VStack(alignment: .leading, spacing: 8) {
                Text("Device name for Viewers")
                    .font(.caption)
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
                Label {
                    Text(model.started ? "Turn off hosting" : "Turn on hosting (no broadcast)")
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                } icon: {
                    Image(systemName: model.started ? "stop.circle.fill" : "play.circle")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white.opacity(0.18))

            // Low-level diagnostics – kept for DEBUG builds only
            #if DEBUG
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
            #endif
        }
        .padding(18)
        .hostGlassCard(cornerRadius: 22)
        .foregroundStyle(.white)
    }
}
