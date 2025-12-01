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
    @Published var hasAutoConnectedToPrimaryHost: Bool = false

    let browser = BeamBrowser()
    let client = BeamControlClient()
    let media = UDPMediaClient()

    private var cancellables: Set<AnyCancellable> = []

    init() {
        media.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func startDiscovery() {
        do {
            try browser.start()

            // If nothing appears after a short delay, hint about permissions.
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

    func pick(_ host: DiscoveredHost) {
        selectedHost = host
        code = BeamControlClient.randomCode()
        BeamLog.info("UI picked host \(host.name)", tag: "viewer")
        showPairSheet = true
        pair()
    }

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
        case .idle, .failed:
            return true
        default:
            return false
        }
    }

    func maybeStartMedia() {
        guard client.broadcastOn else {
            BeamLog.debug("Broadcast is OFF; not starting UDP yet", tag: "viewer")
            return
        }

        guard case .paired(_, let maybePort) = client.status,
              let udpPort = maybePort,
              let sel = selectedHost else {
            return
        }

        let updated = browser.hosts.first { $0.endpoint.debugDescription == sel.endpoint.debugDescription } ?? sel

        if let pref = updated.preferredEndpoint,
           case let .hostPort(host: h, port: _) = pref {
            media.connect(toHost: h, port: udpPort)
            media.armAutoReconnect()
            return
        }

        if let h = client.udpHostCandidate() {
            media.connect(toHost: h, port: udpPort)
            media.armAutoReconnect()
            return
        }

        if case let .hostPort(host: h, port: _) = updated.endpoint {
            media.connect(toHost: h, port: udpPort)
            media.armAutoReconnect()
            return
        }

        BeamLog.warn("No hostPort endpoint available for UDP media", tag: "viewer")
    }

    /// Auto‑connect to a single discovered Host to remove extra taps.
    func autoConnectIfNeeded() {
        guard !hasAutoConnectedToPrimaryHost else { return }
        guard selectedHost == nil else { return }

        switch client.status {
        case .idle, .failed:
            break
        default:
            return
        }

        guard let host = browser.hosts.first,
              browser.hosts.count == 1 else {
            return
        }

        hasAutoConnectedToPrimaryHost = true
        selectedHost = host
        code = BeamControlClient.randomCode()
        BeamLog.info("Auto-selected host \(host.name)", tag: "viewer")

        // Silent auto-pair – no explicit Pair sheet tap needed.
        showPairSheet = false
        pair()
    }
}

struct ViewerRootView: View {
    @StateObject private var model = ViewerViewModel()
    @State private var showLogs = false
    @State private var autoDismissedOnFirstFrame = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.black)
                    .ignoresSafeArea()

                if let cg = model.media.lastImage {
                    // Full-screen video mode once we have a frame
                    GeometryReader { proxy in
                        Image(uiImage: UIImage(cgImage: cg))
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .drawingGroup()
                            .ignoresSafeArea()
                    }
                    .ignoresSafeArea()

                    statsFooter()
                        .padding(.bottom, 16)
                } else {
                    // Discovery / waiting UI before the first frame arrives
                    VStack(spacing: 12) {
                        Text("BeamRoom — Viewer")
                            .font(.largeTitle)
                            .bold()
                            .multilineTextAlignment(.center)

                        awarePickButton()

                        if model.showPermHint && model.browser.hosts.isEmpty {
                            permissionHint
                        }

                        if model.browser.hosts.isEmpty {
                            discoveringView
                        } else {
                            hostList
                            primaryConnectButton()
                        }

                        GeometryReader { proxy in
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.secondary.opacity(0.08))

                                VStack(spacing: 8) {
                                    ProgressView()
                                    Text("Waiting for video…")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .padding()
                }
            }
            .navigationTitle("Viewer")
            .toolbar(model.media.lastImage == nil ? .automatic : .hidden, for: .navigationBar)
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
            .task {
                model.startDiscovery()
            }
            .onDisappear {
                model.stopDiscovery()
            }
            .onChange(of: model.browser.hosts) { _, _ in
                model.autoConnectIfNeeded()
            }
            .onChange(of: model.client.status) { _, new in
                if case .paired = new {
                    model.maybeStartMedia()
                }
            }
            .onChange(of: model.client.broadcastOn) { _, on in
                if on {
                    model.maybeStartMedia()
                }
            }
            .onChange(of: model.media.lastImage) { _, img in
                if img != nil, model.showPairSheet, !autoDismissedOnFirstFrame {
                    autoDismissedOnFirstFrame = true
                    model.showPairSheet = false
                }
            }
            .sheet(isPresented: $model.showPairSheet) {
                PairSheet(model: model)
                    .presentationDetents([.fraction(0.35), .medium])
            }
            .sheet(isPresented: $model.showAwareSheet) {
                awarePickSheet()
            }
            .sheet(isPresented: $showLogs) {
                BeamLogView()
            }
        }
    }
}

// MARK: - Helpers & subviews

private extension ViewerRootView {
    private var primaryHost: DiscoveredHost? {
        if let selected = model.selectedHost {
            return selected
        }
        return model.browser.hosts.first
    }

    @ViewBuilder
    func primaryConnectButton() -> some View {
        if let host = primaryHost {
            Button {
                model.pick(host)
            } label: {
                Label("Connect to \(host.name)", systemImage: "play.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .buttonStyle(.borderedProminent)
        }
    }

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
    var permissionHint: some View {
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
        .background(Color.yellow.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    var discoveringView: some View {
        VStack(spacing: 8) {
            Text("Discovering nearby Hosts…")
                .font(.headline)
            ProgressView()
        }
    }

    @ViewBuilder
    var hostList: some View {
        List(model.browser.hosts) { host in
            Button {
                model.pick(host)
            } label: {
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
        .frame(maxHeight: 220)
    }

    @ViewBuilder
    func statsFooter() -> some View {
        Text(
            String(
                format: "fps %.1f • %.0f kbps • drops %llu",
                model.media.stats.fps,
                model.media.stats.kbps,
                model.media.stats.drops
            )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    func awarePickSheet() -> some View {
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
                label: {
                    Text("Pair Viewer")
                },
                fallback: {
                    VStack(spacing: 12) {
                        Text("Wi-Fi Aware not available.")
                        Button("Close") {
                            model.showAwareSheet = false
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    }
                    .padding()
                }
            )
        } else {
            VStack(spacing: 12) {
                Text("Wi-Fi Aware service not available.")
                Button("Close") {
                    model.showAwareSheet = false
                }
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            }
            .padding()
        }
        #else
        VStack(spacing: 12) {
            Text("Wi-Fi Aware UI isn’t available on this build configuration.")
            Button("Close") {
                model.showAwareSheet = false
            }
            .lineLimit(1)
            .minimumScaleFactor(0.9)
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
                    Text("Pairing with")
                        .font(.headline)
                    Text(host.name)
                        .font(.title3)
                        .bold()
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
                    Text("Ready to pair")
                        .foregroundStyle(.secondary)

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
                        .font(.footnote)
                        .monospaced()
                        .foregroundStyle(.secondary)

                    Label(
                        model.client.broadcastOn ? "Broadcast: On" : "Broadcast: Off",
                        systemImage: model.client.broadcastOn ? "dot.radiowaves.left.right" : "wave.3.right"
                    )
                    .foregroundStyle(model.client.broadcastOn ? .green : .secondary)

                    if let u = udp {
                        Text("Media UDP port: \(u)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let cg = model.media.lastImage {
                        Image(uiImage: UIImage(cgImage: cg))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 160)

                        Text(
                            String(
                                format: "fps %.1f • %.0f kbps • drops %llu",
                                model.media.stats.fps,
                                model.media.stats.kbps,
                                model.media.stats.drops
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Waiting for video…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .failed(let reason):
                    Label("Failed: \(reason)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }

                Spacer()

                HStack {
                    Button("Cancel") {
                        model.cancelPairing()
                    }
                    .buttonStyle(.bordered)

                    if case .paired = model.client.status {
                        Button("Done") {
                            model.showPairSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Pair") {
                            model.pair()
                        }
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
                if case .paired = model.client.status,
                   model.client.broadcastOn {
                    model.maybeStartMedia()
                }
            }
        }
    }
}
