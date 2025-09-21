//
//  ViewerRootView.swift
//  BeamRoomViewer
//
//  Created by . . on 9/21/25.
//
//  M1 UI — discovers Hosts via Bonjour/Wi-Fi Aware and pairs with a 4-digit code.
//

import SwiftUI
import Combine
import Network
import UIKit
import BeamCore
import DeviceDiscoveryUI
import WiFiAware

// MARK: - View model

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var code: String = BeamControlClient.randomCode()
    @Published var selectedHost: DiscoveredHost?
    @Published var showPairSheet: Bool = false
    @Published var showPermHint: Bool = false
    @Published var showAwareSheet: Bool = false

    let browser = BeamBrowser()
    let client  = BeamControlClient()

    func startDiscovery() {
        do {
            try browser.start()
            // If nothing shows after a short while, nudge the user about Local Network perms.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if self.browser.hosts.isEmpty { self.showPermHint = true }
            }
        } catch {
            // No-op for now; UI still shows an empty list + hint.
        }
    }

    func stopDiscovery() {
        browser.stop()
    }

    func pick(_ host: DiscoveredHost) {
        selectedHost = host
        code = BeamControlClient.randomCode()
        client.connect(to: host, code: code)
        showPairSheet = true
    }

    func cancelPairing() {
        client.disconnect()
        showPairSheet = false
    }
}

// MARK: - Root

struct ViewerRootView: View {
    @StateObject private var model = ViewerViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("BeamRoom — Viewer")
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)

                awarePickButton()

                if model.showPermHint && model.browser.hosts.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("If nothing appears, allow Local Network for BeamRoom in Settings.")
                            .font(.footnote)
                        Spacer()
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    .padding(10)
                    .background(.yellow.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if model.browser.hosts.isEmpty {
                    VStack(spacing: 8) {
                        Text("Discovering nearby Hosts…").font(.headline)
                        ProgressView()
                    }
                } else {
                    List(model.browser.hosts) { host in
                        Button { model.pick(host) } label: {
                            HStack {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                Text(host.name)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .frame(maxHeight: 320)
                }

                Spacer(minLength: 12)

                Text(BeamCore.hello()).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Viewer")
            .task { model.startDiscovery() }
            .onDisappear { model.stopDiscovery() }
            .sheet(isPresented: $model.showPairSheet) { PairSheet(model: model) }
            .sheet(isPresented: $model.showAwareSheet) { awarePickSheet() }
        }
    }
}

// MARK: - Aware UI (Viewer = Subscriber only)

private extension ViewerRootView {
    @ViewBuilder
    func awarePickButton() -> some View {
        Button {
            model.showAwareSheet = true
        } label: {
            Label("Find & Pair Host (Wi-Fi Aware)", systemImage: "person.2.wave.2")
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    func awarePickSheet() -> some View {
        // Preflight the Info.plist to avoid framework assertion; only then touch `allServices`.
        if let service = AwareSupport.subscriberService(named: BeamConfig.controlService) {
            let devices: WASubscriberBrowser.Devices = .userSpecifiedDevices
            let provider = WASubscriberBrowser.wifiAware(
                .connecting(to: devices, from: service),
                active: nil
            )

            DevicePicker(
                provider,
                onSelect: { _ in
                    // You can resolve the selected peer into a Network.framework connection
                    // or just continue with Bonjour discovery as we already do.
                    model.showAwareSheet = false
                },
                label: { Text("Pair Viewer") },
                fallback: {
                    VStack(spacing: 12) {
                        Text("Wi-Fi Aware not available.")
                        Button("Close") { model.showAwareSheet = false }
                    }
                    .padding()
                }
            )
        } else {
            VStack(spacing: 12) {
                Text("Wi-Fi Aware service not available.")
                Button("Close") { model.showAwareSheet = false }
            }
            .padding()
        }
    }
}

// MARK: - Pair sheet

private struct PairSheet: View {
    @ObservedObject var model: ViewerViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let host = model.selectedHost {
                    Text("Pairing with").font(.headline)
                    Text(host.name)
                        .font(.title3).bold()
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                Text("Your code")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(model.code)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()

                switch model.client.status {
                case .idle:
                    Text("Idle").foregroundStyle(.secondary)
                case .connecting(let hostName, _):
                    Label("Connecting to \(hostName)…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                case .waitingAcceptance:
                    Label("Waiting for Host to accept…", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                case .paired(let sid, _):
                    Label("Paired ✓", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Session: \(sid.uuidString)")
                        .font(.footnote)
                        .monospaced()
                        .foregroundStyle(.secondary)
                case .failed(let reason):
                    Label("Failed: \(reason)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }

                Spacer()

                HStack {
                    Button("Cancel") { model.cancelPairing() }
                        .buttonStyle(.bordered)

                    if case .paired = model.client.status {
                        Button("Done") { model.showPairSheet = false }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
            .navigationTitle("Pair")
            .presentationDetents([.medium])
        }
    }
}

#Preview {
    ViewerRootView()
}
