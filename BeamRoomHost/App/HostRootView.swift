//
//  HostRootView.swift
//  BeamRoomHost
//
//  Created by . . on 9/21/25.
//
//  Publishes the control service, shows pending pair requests,
//  and (optionally) presents Wi-Fi Aware pairing UI.
//

import SwiftUI
import Combine
import BeamCore
import UIKit
import Network

// Toggle this at build-time if you want the Aware UI included.
#if AWARE_UI_ENABLED
import DeviceDiscoveryUI
import WiFiAware
#endif

// MARK: - View model

@MainActor
final class HostViewModel: ObservableObject {
    @Published var serviceName: String = UIDevice.current.name
    @Published var started: Bool = false

    let server = BeamControlServer()

    func toggle() {
        if started {
            server.stop()
            started = false
        } else {
            do {
                try server.start(serviceName: serviceName)
                started = true
            } catch {
                started = false
            }
        }
    }

    func accept(_ id: UUID)  { server.accept(id) }
    func decline(_ id: UUID) { server.decline(id) }
}

// MARK: - Root view

struct HostRootView: View {
    @StateObject private var model = HostViewModel()
    #if AWARE_UI_ENABLED
    @State private var showAwareSheet = false
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("BeamRoom — Host")
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)

                HStack {
                    TextField("Service Name", text: $model.serviceName)
                        .textFieldStyle(.roundedBorder)

                    Button(model.started ? "Stop" : "Publish") { model.toggle() }
                        .buttonStyle(.borderedProminent)
                }

                // Present Aware UI lazily in a sheet (avoids touching WiFiAware at launch)
                #if AWARE_UI_ENABLED
                awarePairButton()
                #endif

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().frame(width: 10, height: 10)
                            .foregroundStyle(model.started ? .green : .secondary)
                        Text(model.started
                             ? "Advertising \(model.serviceName) on \(BeamConfig.controlService)"
                             : "Not advertising")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    }

                    if !model.server.sessions.isEmpty {
                        Text("Active Sessions").font(.headline)
                        List(model.server.sessions) { s in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(s.id.uuidString)
                                        .font(.footnote).monospaced()
                                    Text(s.remoteDescription)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(s.startedAt, style: .time)
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .listStyle(.plain)
                        .frame(maxHeight: 180)
                    }

                    Text("Pair Requests").font(.headline)

                    if model.server.pendingPairs.isEmpty {
                        Text("None yet.\nA Viewer will tap your name and send a 4-digit code.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    List(model.server.pendingPairs) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Code: \(p.code)")
                                    .font(.title2).bold().monospaced()
                                Text(p.remoteDescription)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Button("Decline") { model.decline(p.id) }
                                    .buttonStyle(.bordered)
                                Button("Accept") { model.accept(p.id) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 120, maxHeight: 240)
                }

                Spacer(minLength: 12)

                #if AWARE_UI_ENABLED
                Text("Wi-Fi Aware UI enabled")
                    .font(.caption).foregroundStyle(.secondary)
                #endif

                Text(BeamCore.hello()).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Host")
            .task {
                // Auto-publish once on first appearance
                if !model.started { model.toggle() }
            }
            #if AWARE_UI_ENABLED
            .sheet(isPresented: $showAwareSheet) { awarePairSheet() }
            #endif
        }
    }
}

// MARK: - Aware UI (Host = Publisher side)

#if AWARE_UI_ENABLED
private extension HostRootView {
    @ViewBuilder
    func awarePairButton() -> some View {
        Button {
            showAwareSheet = true
        } label: {
            Label("Pair with Viewer (Wi-Fi Aware)", systemImage: "dot.radiowaves.left.and.right")
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    func awarePairSheet() -> some View {
        // ✅ Gate on a *valid* Info.plist shape and fetch the publishable service.
        if let service = AwareSupport.publishableService(named: BeamConfig.controlService) {
            let devices: WAPublisherListener.Devices = .userSpecifiedDevices
            let provider: ListenerProvider = .wifiAware(
                .connecting(to: service, from: devices, datapath: .realtime),
                active: nil
            )

            DevicePairingView(provider, access: .default) {
                Text("Pair Host")
            } fallback: {
                VStack(spacing: 12) {
                    Text("Wi-Fi Aware not available.")
                    Button("Close") { showAwareSheet = false }
                }
                .padding()
            }
        } else {
            VStack(spacing: 12) {
                Text("Wi-Fi Aware service not available.")
                Button("Close") { showAwareSheet = false }
            }
            .padding()
        }
    }
}
#endif

#Preview {
    HostRootView()
}
