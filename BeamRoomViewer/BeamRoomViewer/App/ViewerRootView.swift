//
//  ViewerRootView.swift
//  BeamRoomViewer
//
//  Created by . . on 9/21/25.
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
    let media  = UDPMediaClient()

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

    func stopDiscovery() {
        browser.stop()
    }

    // Open the sheet and auto-pair when a host is tapped
    func pick(_ host: DiscoveredHost) {
        selectedHost = host
        code = BeamControlClient.randomCode()
        BeamLog.info("UI picked host \(host.name)", tag: "viewer")
        showPairSheet = true
        pair() // start control connection immediately
    }

    // Connect when the user taps “Pair”
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
        media.disarmAutoReconnect()
        media.disconnect()
        showPairSheet = false
    }

    var canTapPair: Bool {
        switch client.status {
        case .idle, .failed: return true
        default: return false
        }
    }

    // Start UDP video only when Broadcast is ON and we know the port.
    func maybeStartMedia() {
        guard client.broadcastOn else {
            BeamLog.debug("Broadcast is OFF; not starting UDP yet", tag: "viewer")
            return
        }
        guard case .paired(_, let maybePort) = client.status, let udpPort = maybePort else { return }
        guard let sel = selectedHost else { return }

        // Prefer the browser’s resolved endpoint
        let updated = browser.hosts.first { $0.endpoint.debugDescription == sel.endpoint.debugDescription } ?? sel
        if let pref = updated.preferredEndpoint, case let .hostPort(host: h, port: _) = pref {
            media.connect(toHost: h, port: udpPort)
            media.armAutoReconnect()
            return
        }

        // Fallback to the control link’s resolved host
        if let h = client.udpHostCandidate() {
            media.connect(toHost: h, port: udpPort)
            media.armAutoReconnect()
            return
        }

        // Last resort: the original host:port, if applicable
        if case let .hostPort(host: h, port: _) = updated.endpoint {
            media.connect(toHost: h, port: udpPort)
            media.armAutoReconnect()
            return
        }

        BeamLog.warn("No hostPort endpoint available for UDP media", tag: "viewer")
    }
}

struct ViewerRootView: View {
    @StateObject private var model = ViewerViewModel()
    @State private var showLogs = false
    @State private var autoDismissedOnFirstFrame = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 12) {
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
                                        .lineLimit(1).minimumScaleFactor(0.9)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .frame(maxHeight: 220)
                    }

                    // Full-screen(ish) live preview
                    GeometryReader { proxy in
                        if let cg = model.media.lastImage {
                            Image(uiImage: UIImage(cgImage: cg))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                                .drawingGroup() // smoother frequent redraws
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.secondary.opacity(0.08))
                                VStack(spacing: 8) {
                                    ProgressView()
                                    Text("Waiting for video…").foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .ignoresSafeArea(edges: .bottom)

                    // Tiny stats footer
                    Text(String(format: "fps %.1f • %.0f kbps • drops %llu",
                                model.media.stats.fps,
                                model.media.stats.kbps,
                                model.media.stats.drops))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
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

            // When paired, we may or may not have Broadcast ON yet; gate by broadcastOn.
            .onChange(of: model.client.status) { _, new in
                if case .paired = new { model.maybeStartMedia() }
            }

            // As soon as Host flips Broadcast → ON, start UDP immediately.
            .onChange(of: model.client.broadcastOn) { _, on in
                if on { model.maybeStartMedia() }
            }

            // Auto-dismiss Pair sheet once the first frame arrives so the preview is visible
            .onChange(of: model.media.lastImage) { _, img in
                if img != nil, model.showPairSheet, !autoDismissedOnFirstFrame {
                    autoDismissedOnFirstFrame = true
                    model.showPairSheet = false
                }
            }

            // Pairing UI
            .sheet(isPresented: $model.showPairSheet) {
                PairSheet(model: model)
                    .presentationDetents([.fraction(0.35), .medium])
            }

            // Wi-Fi Aware picker
            .sheet(isPresented: $model.showAwareSheet) {
                awarePickSheet()
            }

            // Logs
            .sheet(isPresented: $showLogs) {
                BeamLogView()
            }
        }
    }
}

// MARK: - Helpers & subviews
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
        #if canImport(DeviceDiscoveryUI) && canImport(WiFiAware)
        if let service = AwareSupport.subscriberService(named: BeamConfig.controlService) {
            let devices: WASubscriberBrowser.Devices = .userSpecifiedDevices
            let provider = WASubscriberBrowser.wifiAware(
                .connecting(to: devices, from: service), active: nil
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
                    }
                    .padding()
                }
            )
        } else {
            VStack(spacing: 12) {
                Text("Wi-Fi Aware service not available.")
                Button("Close") { model.showAwareSheet = false }
                    .lineLimit(1).minimumScaleFactor(0.9)
            }
            .padding()
        }
        #else
        VStack(spacing: 12) {
            Text("Wi-Fi Aware UI isn’t available on this build configuration.")
            Button("Close") { model.showAwareSheet = false }
                .lineLimit(1).minimumScaleFactor(0.9)
        }
        .padding()
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
                        .lineLimit(2).minimumScaleFactor(0.8)
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
                    }

                    if let cg = model.media.lastImage {
                        Image(uiImage: UIImage(cgImage: cg))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 160)
                        Text(String(format: "fps %.1f • %.0f kbps • drops %llu",
                                    model.media.stats.fps,
                                    model.media.stats.kbps,
                                    model.media.stats.drops))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Waiting for video…")
                            .font(.caption).foregroundStyle(.secondary)
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
            .presentationDetents([.fraction(0.35), .medium])
            .onChange(of: model.client.status) { _, new in
                if case .paired = new, !firedSuccessHaptic {
                    firedSuccessHaptic = true
                    let gen = UINotificationFeedbackGenerator()
                    gen.notificationOccurred(.success)
                }
            }
            .onAppear {
                // If we’re already paired and Broadcast is ON, start media.
                model.maybeStartMedia()
            }
        }
    }
}

#Preview { ViewerRootView() }
