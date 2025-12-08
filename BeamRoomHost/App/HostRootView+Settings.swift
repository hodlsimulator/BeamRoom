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
            HStack {
                HStack(spacing: 8) {
                    HostStepChip(number: 0, label: "Optional")

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
        .hostGlassCard(cornerRadius: 22)
        .foregroundStyle(.white)
    }
}
