//
//  ViewerRootView.swift
//  BeamRoomViewer
//
//  Created by . . on 9/21/25.
//
//  M1 UI — discovery + pairing; M3 preview: receives fake frames over UDP.
//

import SwiftUI
import Combine
import Network
import UIKit
import BeamCore

#if canImport(DeviceDiscoveryUI)
import DeviceDiscoveryUI
#endif
#if canImport(WiFiAware)
import WiFiAware
#endif

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var code: String = BeamControlClient.randomCode()
    @Published var selectedHost: DiscoveredHost?
    @Published var showPairSheet: Bool = false
    @Published var showPermHint: Bool = false
    @Published var showAwareSheet: Bool = false

    let browser = BeamBrowser()
    let client = BeamControlClient()
    let media = UDPMediaClient()

    func startDiscovery() {
        do {
            try browser.start()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if self.browser.hosts.isEmpty {
                    self.showPermHint = true
                }
            }
        } catch {
            BeamLog.error("Discovery start error: \(error.localizedDescription)", tag: "viewer")
        }
    }

    func stopDiscovery() {
        browser.stop()
    }

    // Don’t connect here — just open the sheet with a fresh code
    func pick(_ host: DiscoveredHost) {
        selectedHost = host
        code = BeamControlClient.randomCode()
        BeamLog.info("UI picked host \(host.name)", tag: "viewer")
        showPairSheet = true
    }

    // Connect when the user taps “Pair” in the sheet
    func pair() {
        guard let host = selectedHost else { return }
        switch client.status {
        case .idle, .failed:
            client.connect(to: host, code: code)
        default:
            BeamLog.warn("Pair tap ignored; client.status=\(String(describing: client.status))", tag: "viewer")
        }
    }

    func cancelPairing() {
        client.disconnect()
        media.disconnect()
        showPairSheet = false
    }

    var canTapPair: Bool {
        switch client.status {
        case .idle, .failed: return true
        default: return false
        }
    }

    // MARK: M3 preview bootstrap (fixed)
    func maybeStartMedia() {
        guard case .paired(_, let maybePort) = client.status, let udpPort = maybePort else { return }
        guard let sel = selectedHost else { return }

        // Re-acquire the freshest copy of this host from the browser (the one with resolved IPv4)
        let updated = browser.hosts.first { $0.endpoint.debugDescription == sel.endpoint.debugDescription } ?? sel

        // 1) Prefer resolved IPv4 endpoint from the browser
        if let pref = updated.preferredEndpoint, case let .hostPort(host: h, port: _) = pref {
            media.connect(toHost: h, port: udpPort)
            return
        }

        // 2) Fall back to the *connected* control link’s resolved remote host
        if let h = client.udpHostCandidate() {
            media.connect(toHost: h, port: udpPort)
            return
        }

        // 3) Last resort: if the original endpoint was already a host:port
        if case let .hostPort(host: h, port: _) = updated.endpoint {
            media.connect(toHost: h, port: udpPort)
            return
        }

        // If we reach here, we still don’t have a host IP to dial for UDP
        BeamLog.warn("No hostPort endpoint available for UDP media", tag: "viewer")
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

                // Tiny always-on preview if we’re receiving frames
                if let cg = model.media.lastImage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preview (Test Stream)").font(.headline)
                        Image(uiImage: UIImage(cgImage: cg))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 180)
                        Text(String(format: "fps %.1f • %.0f kbps • drops %llu",
                                    model.media.stats.fps,
                                    model.media.stats.kbps,
                                    model.media.stats.drops))
                        .font(.caption).foregroundStyle(.secondary)
                    }
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
                    Button { showLogs = true } label: {
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
    @ViewBuilder func awarePickButton() -> some View {
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

    @ViewBuilder func awarePickSheet() -> some View {
        #if canImport(DeviceDiscoveryUI) && canImport(WiFiAware)
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
                            .lineLimit(1).minimumScaleFactor(0.9)
                    }.padding()
                }
            )
        } else {
            VStack(spacing: 12) {
                Text("Wi-Fi Aware service not available.")
                Button("Close") { model.showAwareSheet = false }
                    .lineLimit(1).minimumScaleFactor(0.9)
            }.padding()
        }
        #else
        VStack(spacing: 12) {
            Text("Wi-Fi Aware UI isn’t available on this build configuration.")
            Button("Close") { model.showAwareSheet = false }
                .lineLimit(1).minimumScaleFactor(0.9)
        }.padding()
        #endif
    }
}

// MARK: - Pair Sheet

private struct PairSheet: View {
    @ObservedObject var model: ViewerViewModel
    @State private var firedSuccessHaptic = false

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

                Text("Your code").font(.caption).foregroundStyle(.secondary)
                Text(model.code)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()

                switch model.client.status {
                case .idle:
                    Text("Ready to pair").foregroundStyle(.secondary)

                case .connecting(let hostName, _):
                    Label("Connecting to \(hostName)…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)

                case .waitingAcceptance:
                    Label("Waiting for Host to accept…", systemImage: "hourglass")
                        .foregroundStyle(.secondary)

                case .paired(let sid, let udp):
                    Label("Paired ✓", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Session: \(sid.uuidString)")
                        .font(.footnote).monospaced().foregroundStyle(.secondary)
                    Label(model.client.broadcastOn ? "Broadcast: On" : "Broadcast: Off",
                          systemImage: model.client.broadcastOn ? "dot.radiowaves.left.right" : "wave.3.right")
                        .foregroundStyle(model.client.broadcastOn ? .green : .secondary)

                    if let u = udp {
                        Text("Media UDP port: \(u)")
                            .font(.caption).foregroundStyle(.secondary)

                        if let cg = model.media.lastImage {
                            Image(uiImage: UIImage(cgImage: cg))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 180)
                            Text(String(format: "fps %.1f • %.0f kbps • drops %llu",
                                        model.media.stats.fps,
                                        model.media.stats.kbps,
                                        model.media.stats.drops))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Waiting for test frames…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

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
                    } else {
                        Button("Pair") { model.pair() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canTapPair)
                    }
                }
            }
            .padding()
            .navigationTitle("Pair")
            .presentationDetents([.medium])
            .onChange(of: model.client.status) { _, new in
                if case .paired = new, !firedSuccessHaptic {
                    firedSuccessHaptic = true
                    let gen = UINotificationFeedbackGenerator()
                    gen.notificationOccurred(.success)
                }
                // Kick UDP hello when we learn the udpPort.
                if case .paired = new { model.maybeStartMedia() }
            }
            .onAppear { model.maybeStartMedia() }
        }
    }
}

#Preview {
    ViewerRootView()
}
