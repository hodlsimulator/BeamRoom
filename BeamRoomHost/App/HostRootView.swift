//
//  HostRootView.swift
//  BeamRoomHost
//
//  Created by . . on 9/21/25.
//

import SwiftUI
import Combine
import OSLog
import ReplayKit
import UIKit
import BeamCore

// MARK: - View model

@MainActor
final class HostViewModel: ObservableObject {
    @Published var serviceName: String = UIDevice.current.name
    @Published var started: Bool = false
    @Published var autoAccept: Bool
    @Published var broadcastOn: Bool = BeamConfig.isBroadcastOn()
    @Published var sessions: [BeamControlServer.ActiveSession] = []
    @Published var pendingPairs: [BeamControlServer.PendingPair] = []
    @Published var udpPeer: String? = nil

    let server: BeamControlServer

    private var cancellables = Set<AnyCancellable>()
    private var broadcastPoll: DispatchSourceTimer?

    init() {
        let auto = BeamConfig.autoAcceptDuringTest
        self.server = BeamControlServer(autoAccept: auto)
        self.autoAccept = auto

        server.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.sessions = $0
            }
            .store(in: &cancellables)

        server.$pendingPairs
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.pendingPairs = $0
            }
            .store(in: &cancellables)

        server.$udpPeer
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.udpPeer = $0
            }
            .store(in: &cancellables)

        // If the Screen Broadcast is already running (for example started from
        // Control Centre before the app launches), automatically start hosting
        // so Viewers can reconnect without extra taps.
        if BeamConfig.isBroadcastOn() {
            startServer()
        }
    }

    // MARK: - Public API

    func toggleServer() {
        if started {
            stopServer()
        } else {
            startServer()
        }
    }

    func setAutoAccept(_ value: Bool) {
        autoAccept = value
        server.autoAccept = value
    }

    func accept(_ pendingID: UUID) {
        server.accept(pendingID)
    }

    func decline(_ pendingID: UUID) {
        server.decline(pendingID)
    }

    // MARK: - Server lifecycle

    private func startServer() {
        guard !started else { return }

        do {
            try server.start(serviceName: serviceName)
            started = true
            startBroadcastPoll()

            if BeamConfig.isBroadcastOn() {
                BackgroundAudioKeeper.shared.start()
                broadcastOn = true
            } else {
                broadcastOn = false
            }
        } catch {
            BeamLog.error("Failed to start host: \(error.localizedDescription)", tag: "host")
        }
    }

    private func stopServer() {
        guard started else { return }

        server.stop()
        started = false
        stopBroadcastPoll()
        broadcastOn = false
        BackgroundAudioKeeper.shared.stop()
    }

    // MARK: - Broadcast polling → drives background audio

    private func startBroadcastPoll() {
        stopBroadcastPoll()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)

        timer.setEventHandler { [weak self] in
            guard let self else { return }

            let on = BeamConfig.isBroadcastOn()

            Task { @MainActor in
                guard self.started else { return }

                if on != self.broadcastOn {
                    self.broadcastOn = on

                    if on {
                        BackgroundAudioKeeper.shared.start()
                    } else {
                        BackgroundAudioKeeper.shared.stop()
                    }
                }
            }
        }

        timer.resume()
        broadcastPoll = timer
    }

    private func stopBroadcastPoll() {
        broadcastPoll?.cancel()
        broadcastPoll = nil
    }
}

// MARK: - Host view

struct HostRootView: View {
    @StateObject private var model = HostViewModel()
    @StateObject private var broadcastController = BroadcastLaunchController()

    @State private var showingAbout = false
    @State private var showingBroadcastHelp = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    heroCard
                    hostSettingsCard
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 40) // space above pinned pairing card
            }
            .background(
                LinearGradient(
                    colors: [
                        Color.black,
                        Color.black,
                        Color(uiColor: .systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Share")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About BeamRoom")
                }
            }
            .safeAreaInset(edge: .bottom) {
                pairingCard
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            }
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .confirmationDialog(
            "Screen broadcast help",
            isPresented: $showingBroadcastHelp,
            titleVisibility: .visible
        ) {
            Button("Open Screen Broadcast controls") {
                broadcastController.startBroadcast()
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "If the sheet does not appear, open Control Centre, long‑press Screen Recording, choose “BeamRoom”, then tap Start Broadcast.\n\nOnce broadcasting, video is sent to paired Viewers even while this app is in the background."
            )
        }
        .onAppear {
            // If a Broadcast is already running (for example started from
            // Control Centre), automatically start hosting so Viewers can
            // connect without extra taps.
            if model.broadcastOn, !model.started {
                model.toggleServer()
            }
        }
    }

    // MARK: - Main hero card

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.95),
                            Color.accentColor.opacity(0.7),
                            Color.purple.opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(heroTitle)
                            .font(.title2.weight(.semibold))

                        Text(heroSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    Spacer()

                    if model.broadcastOn {
                        LiveBadge(text: "Live")
                    } else if model.started {
                        LiveBadge(text: "Ready")
                    } else {
                        Image(systemName: "rectangle.on.rectangle.badge.person.crop")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.16))
                            )
                    }
                }

                Button {
                    startQuickShare()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.broadcastOn ? "dot.radiowaves.left.and.right" : "play.fill")
                            .imageScale(.large)

                        Text(model.broadcastOn ? "Manage broadcast" : "Start sharing")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundColor(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    model.broadcastOn
                    ? "Open Screen Broadcast controls"
                    : "Start hosting and open Screen Broadcast sheet"
                )

                statusPills

                if !model.broadcastOn {
                    Button {
                        showingBroadcastHelp = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark.circle")
                                .imageScale(.small)
                            Text("Problems starting the broadcast?")
                                .font(.footnote.weight(.medium))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }

                // Hidden system picker – the large button taps this internally.
                BroadcastPickerShim(controller: broadcastController)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)
            }
            .padding(20)
            .foregroundStyle(.white)
        }
    }

    private var heroTitle: String {
        if model.broadcastOn {
            return "Streaming to Viewers"
        } else if model.started {
            return "Hosting is ready"
        } else {
            return "Share this screen"
        }
    }

    private var heroSubtitle: String {
        if model.broadcastOn {
            return "Everything on the screen is mirrored to connected devices."
        } else if model.started {
            return "Start the Screen Broadcast when ready to go live."
        } else {
            return "Start hosting and open the Screen Broadcast sheet in one tap."
        }
    }

    // MARK: - Host settings card

    private var hostSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Host settings")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("Optional")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemBackground))
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
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
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
                Label(
                    model.started ? "Stop hosting only" : "Start hosting only",
                    systemImage: model.started ? "stop.circle.fill" : "play.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        )
    }

    // MARK: - Pairing card (pinned)

    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.wave.2.fill")
                        .imageScale(.large)

                    Text("Pairing")
                        .font(.headline)
                }

                Spacer()

                if model.broadcastOn {
                    LiveBadge(text: "Live")
                } else if model.started {
                    LiveBadge(text: "Host on")
                }
            }

            if model.pendingPairs.isEmpty && model.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Waiting for Viewers to pair…")
                        .font(.subheadline.weight(.medium))

                    Text("Ask the Viewer to open BeamRoom on another device and choose Watch.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            ForEach(model.pendingPairs) { pending in
                VStack(alignment: .leading, spacing: 10) {
                    Text(pending.remoteDescription)
                        .font(.subheadline.weight(.semibold))

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("Pair code")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))

                        Text(pending.code)
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                    }

                    HStack(spacing: 12) {
                        Button(role: .cancel) {
                            model.decline(pending.id)
                        } label: {
                            Text("Decline")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.accept(pending.id)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark")
                                Text("Pair viewer")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white)
                            )
                            .foregroundColor(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Accept pairing with \(pending.remoteDescription)")
                    }
                }
            }

            if !model.sessions.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.3))

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.sessions) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.remoteDescription)

                                Text("Connected \(session.startedAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .imageScale(.large)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor,
                            Color.blue.opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 8)
    }

    // MARK: - Helpers

    private var viewerCountLabel: String {
        let count = model.sessions.count

        switch count {
        case 0:
            return "No viewers"
        case 1:
            return "1 viewer"
        default:
            return "\(count) viewers"
        }
    }

    private var statusPills: some View {
        HStack(spacing: 8) {
            StatusPill(
                icon: model.started ? "wifi.router.fill" : "wifi.slash",
                label: model.started ? "Hosting on" : "Not hosting"
            )

            StatusPill(
                icon: "person.2.fill",
                label: viewerCountLabel
            )

            StatusPill(
                icon: model.broadcastOn ? "dot.radiowaves.left.right" : "wave.3.right",
                label: model.broadcastOn ? "Broadcast on" : "Broadcast off"
            )
        }
        .font(.caption2)
    }

    /// Ensures the server is running, then taps the hidden Broadcast picker.
    private func startQuickShare() {
        if !model.started {
            model.toggleServer()
        }

        broadcastController.startBroadcast()
    }
}

// MARK: - Small reusable views

private struct StatusPill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .imageScale(.small)

            Text(label)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.16))
        )
    }
}

private struct LiveBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                )

            Text(text.uppercased())
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.16))
        )
        .foregroundStyle(.white)
    }
}

// MARK: - Broadcast picker shim

final class BroadcastLaunchController: ObservableObject {
    fileprivate weak var pickerView: RPSystemBroadcastPickerView?

    func startBroadcast() {
        guard let pickerView else { return }

        for subview in pickerView.subviews {
            if let button = subview as? UIButton {
                button.sendActions(for: .touchUpInside)
                break
            }
        }
    }
}

/// Invisible RPSystemBroadcastPickerView wired to a controller.
/// The large SwiftUI button calls `startBroadcast()` which taps it.
struct BroadcastPickerShim: UIViewRepresentable {
    @ObservedObject var controller: BroadcastLaunchController

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView()
        picker.showsMicrophoneButton = true

        // Let the system show all upload extensions; selection is made from the list.
        picker.preferredExtension = nil

        controller.pickerView = picker
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        controller.pickerView = uiView
    }
}
