//
//  ViewerRootView.swift
//  BeamRoomHost
//
//  Created by . . on 9/21/25.
//

// ViewerRootView.swift
// BeamRoomHost

import SwiftUI
import Combine
import Network
import UIKit
import BeamCore

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
        if let preferred = updated.preferredEndpoint,
           case let .hostPort(host: host, port: _) = preferred {
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

        guard let host = browser.hosts.first, browser.hosts.count == 1 else { return }

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
    @StateObject var model = ViewerViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAbout = false
    @State private var autoDismissedOnFirstFrame = false

    var body: some View {
        NavigationStack {
            ZStack {
                liquidBackground

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
            .safeAreaInset(edge: .bottom) {
                if model.media.lastImage == nil {
                    bottomControlsCard
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                }
            }
        }
        // Same as Share tab: force a dark toolbar so the title is white on the dark background.
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            model.startDiscovery()
        }
        .onDisappear {
            model.stopDiscovery()
            updateIdleTimer(forHasVideo: false)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // App became active again (for example after a phone call) –
                // ensure the UDP media path is in a healthy state.
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

// MARK: - Layout helpers that stay in this file

private extension ViewerRootView {
    /// Keeps the device awake while there is live video on screen.
    func updateIdleTimer(forHasVideo hasVideo: Bool) {
        let desired = hasVideo
        if UIApplication.shared.isIdleTimerDisabled != desired {
            UIApplication.shared.isIdleTimerDisabled = desired
        }
    }
}
