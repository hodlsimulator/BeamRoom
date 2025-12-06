//
//  ViewerRootView.swift
//  BeamRoomHost
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

// MARK: - View model

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
        // Propagate media changes into the SwiftUI tree.
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
            BeamLog.warn(
                "Pair tap ignored; client.status=\(String(describing: client.status))",
                tag: "viewer"
            )
        }
    }

    func cancelPairing() {
        client.disconnect()
        media.disarmAutoReconnect()
        media.disconnect()

        // Treat this as a full reset so a later Host restart behaves like a fresh session.
        selectedHost = nil
        hasAutoConnectedToPrimaryHost = false
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

    /// Start UDP media if paired and Broadcast is reported as ON.
    func maybeStartMedia() {
        // Only start UDP when the Host says the broadcast is ON.
        guard client.broadcastOn else {
            BeamLog.debug("Broadcast is OFF; not starting UDP yet", tag: "viewer")
            return
        }

        guard
            case .paired(_, let maybePort) = client.status,
            let udpPort = maybePort,
            let selected = selectedHost
        else {
            return
        }

        // Prefer the latest resolved Host from the browser if available.
        let updated = browser.hosts.first {
            $0.endpoint.debugDescription == selected.endpoint.debugDescription
        } ?? selected

        // 1) Prefer resolved IPv4/IPv6 endpoint.
        if
            let preferred = updated.preferredEndpoint,
            case let .hostPort(host: host, port: _) = preferred
        {
            media.connect(toHost: host, port: udpPort)
            media.armAutoReconnect()
            return
        }

        // 2) Fallback: resolved host from control connection.
        if let host = client.udpHostCandidate() {
            media.connect(toHost: host, port: udpPort)
            media.armAutoReconnect()
            return
        }

        // 3) Last resort: original Bonjour endpoint.
        if case let .hostPort(host: host, port: _) = updated.endpoint {
            media.connect(toHost: host, port: udpPort)
            media.armAutoReconnect()
            return
        }

        BeamLog.warn("No hostPort endpoint available for UDP media", tag: "viewer")
    }

    /// Called when the app returns to the foreground (for example after a phone call).
    /// If still logically paired and Broadcast is ON, force a fresh UDP media connection.
    func restartMediaAfterForegroundIfNeeded() {
        guard client.broadcastOn else { return }
        guard case .paired = client.status else { return }

        // Drop any potentially stale UDP socket and reconnect via the normal path.
        media.disarmAutoReconnect()
        media.disconnect()
        maybeStartMedia()
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

        guard let host = browser.hosts.first, browser.hosts.count == 1 else {
            return
        }

        hasAutoConnectedToPrimaryHost = true
        selectedHost = host
        code = BeamControlClient.randomCode()
        BeamLog.info("Auto-selected host \(host.name)", tag: "viewer")

        // Silent auto‑pair – no explicit Pair sheet tap needed.
        showPairSheet = false
        pair()
    }
}

// MARK: - Root view

struct ViewerRootView: View {

    @StateObject private var model = ViewerViewModel()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showAbout = false
    @State private var autoDismissedOnFirstFrame = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let cgImage = model.media.lastImage {
                    videoView(cgImage)
                } else {
                    idleStateView
                }
            }
            .navigationTitle("Watch")
            .toolbar(model.media.lastImage == nil ? .automatic : .hidden, for: .navigationBar)
            .toolbar(model.media.lastImage == nil ? .automatic : .hidden, for: .tabBar)
            .toolbar {
                if model.media.lastImage == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAbout = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .accessibilityLabel("About BeamRoom")
                    }
                }
            }
        }
        .task {
            model.startDiscovery()
        }
        .onDisappear {
            model.stopDiscovery()
            updateIdleTimer(forHasVideo: false)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // App became active again (for example after a phone call) – ensure
                // the UDP media path is in a healthy state.
                model.restartMediaAfterForegroundIfNeeded()
            }
        }
        .onChange(of: model.browser.hosts) { _, newHosts in
            // If the Host disappeared completely, clear selection so the next
            // appearance is treated as a fresh session and auto‑connect can run.
            if newHosts.isEmpty {
                model.selectedHost = nil
                model.hasAutoConnectedToPrimaryHost = false
            }
            model.autoConnectIfNeeded()
        }
        .onChange(of: model.client.status) { _, newStatus in
            switch newStatus {
            case .paired:
                // Newly paired or re‑paired → ensure UDP media is running.
                model.maybeStartMedia()

            case .failed, .idle:
                // Lost contact with Host or explicitly disconnected.
                // Tear down UDP so there is no frozen last frame and allow a
                // completely fresh auto‑connect / pairing on the next Host.
                model.media.disarmAutoReconnect()
                model.media.disconnect()
                model.selectedHost = nil
                model.hasAutoConnectedToPrimaryHost = false

            default:
                break
            }
        }
        .onChange(of: model.client.broadcastOn) { _, on in
            if on {
                // Broadcast turned ON → start or restart UDP media.
                model.maybeStartMedia()
            } else {
                // Broadcast turned OFF → drop UDP media so the Viewer
                // shows idle state instead of a frozen last frame.
                model.media.disarmAutoReconnect()
                model.media.disconnect()
            }
        }
        .onChange(of: model.media.lastImage) { _, image in
            let hasVideo = (image != nil)
            updateIdleTimer(forHasVideo: hasVideo)

            if hasVideo, model.showPairSheet, !autoDismissedOnFirstFrame {
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
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }
}

// MARK: - Layout helpers

private extension ViewerRootView {

    /// Keeps the device awake while there is live video on screen.
    func updateIdleTimer(forHasVideo hasVideo: Bool) {
        let desired = hasVideo
        if UIApplication.shared.isIdleTimerDisabled != desired {
            UIApplication.shared.isIdleTimerDisabled = desired
        }
    }

    // Idle state before any video arrives.
    var idleStateView: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Join a screen")
                    .font(.title)
                    .bold()
                    .foregroundColor(.white)

                Text(idleSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            if model.browser.hosts.isEmpty {
                discoveringView
            } else {
                primaryConnectButton()

                if model.browser.hosts.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Other nearby Hosts")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        hostList
                    }
                }
            }

            if model.showPermHint && model.browser.hosts.isEmpty {
                permissionHint
            }

            Spacer()

            bottomControls
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 16)
    }

    // Active video mode with a minimal control overlay.
    @ViewBuilder
    func videoView(_ cgImage: CGImage) -> some View {
        Image(uiImage: UIImage(cgImage: cgImage))
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .background(Color.black)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button {
                    model.cancelPairing()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .padding(8)
                }
                .background(.thinMaterial)
                .clipShape(Circle())
                .padding(.top, 16)
                .padding(.trailing, 16)
                .accessibilityLabel("Stop viewing")
            }
    }

    private var idleSubtitle: String {
        let count = model.browser.hosts.count

        if count == 0 {
            return "Once a Host on this network starts sharing, it appears here."
        } else if count == 1 {
            return """
            Found 1 nearby Host.
            Connect to start watching.
            """
        } else {
            return """
            Found \(count) nearby Hosts. Choose one to start watching.
            """
        }
    }

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
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .imageScale(.large)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect to")
                            .font(.caption)
                            .opacity(0.9)
                        Text(host.name)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    var discoveringView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(.white)
            Text("Looking for nearby Hosts on this network…")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    var hostList: some View {
        VStack(spacing: 8) {
            ForEach(model.browser.hosts) { host in
                Button {
                    model.pick(host)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .imageScale(.medium)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.name)
                                .font(.body)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)

                            Text("Tap to connect")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    var permissionHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)

            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing showing up?")
                    .font(.footnote.weight(.semibold))

                Text("Local Network access for BeamRoom may need to be enabled in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Button("Open") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .font(.footnote)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    var bottomControls: some View {
        HStack {
            awarePickButton()
            Spacer()
            connectionStatus
        }
    }

    @ViewBuilder
    func awarePickButton() -> some View {
        Button {
            model.showAwareSheet = true
        } label: {
            Label("Nearby pairing", systemImage: "antenna.radiowaves.left.and.right")
                .font(.footnote)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    var connectionStatus: some View {
        switch model.client.status {
        case .idle:
            EmptyView()

        case .connecting(let hostName, _):
            Label("Connecting to \(hostName)…", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)

        case .waitingAcceptance:
            Label("Waiting for Host…", systemImage: "hourglass")
                .font(.footnote)
                .foregroundStyle(.secondary)

        case .paired:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)

        case .failed:
            Label("Connection failed", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
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
                        Text("Wi‑Fi Aware not available.")
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
                Text("Wi‑Fi Aware service not available.")
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
            Text("Wi‑Fi Aware UI is not available on this build configuration.")
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

                Text("Code for this Viewer")
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
                    Label("Connecting to \(hostName)…",
                          systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)

                case .waitingAcceptance:
                    Label("Waiting for Host to accept…", systemImage: "hourglass")
                        .foregroundStyle(.secondary)

                case .paired(let sid, let udpPort):
                    Label("Paired ✓", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)

                    Text("Session: \(sid.uuidString)")
                        .font(.footnote)
                        .monospaced()
                        .foregroundStyle(.secondary)

                    Label(
                        model.client.broadcastOn ? "Broadcast: On" : "Broadcast: Off",
                        systemImage: model.client.broadcastOn
                            ? "dot.radiowaves.left.right"
                            : "wave.3.right"
                    )
                    .foregroundStyle(model.client.broadcastOn ? .green : .secondary)

                    if let udpPort {
                        Text("Media UDP port: \(udpPort)")
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
            .onChange(of: model.client.status) { _, newStatus in
                if case .paired = newStatus, !firedSuccessHaptic {
                    firedSuccessHaptic = true
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
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
