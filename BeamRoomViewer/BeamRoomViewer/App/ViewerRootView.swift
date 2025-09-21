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
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if self.browser.hosts.isEmpty { self.showPermHint = true }
            }
        } catch {
            BeamLog.error("Discovery start error: \(error.localizedDescription)", tag: "viewer")
        }
    }

    func stopDiscovery() { browser.stop() }

    func pick(_ host: DiscoveredHost) {
        selectedHost = host
        code = BeamControlClient.randomCode()
        BeamLog.info("UI picked host \(host.name)", tag: "viewer")
        client.connect(to: host, code: code)
        showPairSheet = true
    }

    func cancelPairing() {
        client.disconnect()
        showPairSheet = false
    }
}

struct ViewerRootView: View {
    @StateObject private var model = ViewerViewModel()
    @State private var showLogs = false

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
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                        Spacer(minLength: 6)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
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
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.9)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .frame(maxHeight: 320)
                }

                Spacer(minLength: 12)

                Text(BeamCore.hello())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding()
            .navigationTitle("Viewer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLogs = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .lineLimit(1)
                }
            }
            .task { model.startDiscovery() }
            .onDisappear { model.stopDiscovery() }
            .sheet(isPresented: $model.showPairSheet) { PairSheet(model: model) }
            .sheet(isPresented: $model.showAwareSheet) { awarePickSheet() }
            .sheet(isPresented: $showLogs) { BeamLogView() }
        }
    }
}

private extension ViewerRootView {
    @ViewBuilder
    func awarePickButton() -> some View {
        Button {
            model.showAwareSheet = true
        } label: {
            Label("Find & Pair Host (Wi-Fi Aware)", systemImage: "person.2.wave.2")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    func awarePickSheet() -> some View {
        if let service = AwareSupport.subscriberService(named: BeamConfig.controlService) {
            let devices: WASubscriberBrowser.Devices = .userSpecifiedDevices
            let provider = WASubscriberBrowser.wifiAware(
                .connecting(to: devices, from: service),
                active: nil
            )

            DevicePicker(
                provider,
                onSelect: { _ in
                    BeamLog.info("Aware picker selection", tag: "viewer")
                    model.showAwareSheet = false
                },
                label: { Text("Pair Viewer") },
                fallback: {
                    VStack(spacing: 12) {
                        Text("Wi-Fi Aware not available.")
                        Button("Close") { model.showAwareSheet = false }
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .padding()
                }
            )
        } else {
            VStack(spacing: 12) {
                Text("Wi-Fi Aware service not available.")
                Button("Close") { model.showAwareSheet = false }
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .padding()
        }
    }
}

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
                        .minimumScaleFactor(0.8)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                case .waitingAcceptance:
                    Label("Waiting for Host to accept…", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                case .paired(let sid, _):
                    Label("Paired ✓", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .lineLimit(1)
                    Text("Session: \(sid.uuidString)")
                        .font(.footnote)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                case .failed(let reason):
                    Label("Failed: \(reason)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                HStack {
                    Button("Cancel") { model.cancelPairing() }
                        .buttonStyle(.bordered)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)

                    if case .paired = model.client.status {
                        Button("Done") { model.showPairSheet = false }
                            .buttonStyle(.borderedProminent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                }
            }
            .padding()
            .navigationTitle("Pair")
            .presentationDetents([.medium])
        }
    }
}

#Preview { ViewerRootView() }
