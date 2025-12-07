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
            ScrollView {
                VStack(spacing: 16) {
                    quickStartCard
                    hostSettingsCard
                    broadcastHelpRow
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32) // extra space above the pinned pairing card
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
            // Pinned pairing card – always visible at the bottom
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

    // MARK: - Cards

    /// Top card: one big button that both starts hosting and opens the Broadcast sheet.
    private var quickStartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick start")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                if !model.broadcastOn {
                    if !model.started {
                        // Step 1 – Start hosting + prepare broadcast.
                        Text("Start sharing")
                            .font(.headline)
                        Text("Starts hosting and opens the Screen Broadcast sheet so nearby Viewers can connect.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        // Step 2 – Just start the Screen Broadcast.
                        Text("Start Screen Broadcast")
                            .font(.headline)
                        Text("Start the Screen Broadcast so the screen is mirrored to paired Viewers.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Streaming live")
                        .font(.headline)
                    Text("Broadcast is ON. Open the Screen Broadcast controls to stop or restart.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    startQuickShare()
                } label: {
                    Label(
                        model.broadcastOn
                            ? "Open Screen Broadcast controls"
                            : (model.started ? "Start Screen Broadcast" : "Start sharing"),
                        systemImage: model.broadcastOn
                            ? "dot.radiowaves.left.and.right"
                            : "play.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                // Hidden system picker – this is what actually talks to ReplayKit.
                BroadcastPickerShim(controller: broadcastController)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)

                statusSummary
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.thinMaterial)
            )
        }
    }

    /// Host configuration in a compact card.
    private var hostSettingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Host")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Service name", text: $model.serviceName)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

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
                        model.started ? "Stop hosting" : "Start hosting",
                        systemImage: model.started ? "stop.circle.fill" : "play.circle.fill"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                if let peer = model.udpPeer {
                    Label("UDP peer: \(peer)", systemImage: "dot.radiowaves.left.and.right")
                        .font(.footnote)
                } else {
                    Label("UDP peer: none", systemImage: "dot.radiowaves.left.and.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }

    /// Small row that replaces the old tall "Screen broadcast" section.
    private var broadcastHelpRow: some View {
        Button {
            showingBroadcastHelp = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .imageScale(.medium)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Problems starting the broadcast?")
                        .font(.subheadline)
                    Text("Open the Screen Broadcast controls and follow the steps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25))
            )
        }
        .buttonStyle(.plain)
    }

    /// Pinned bottom card – pairing is always visible and visually prominent.
    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pairing", systemImage: "person.2.fill")
                    .font(.headline)

                Spacer()

                if !model.sessions.isEmpty {
                    Text(viewerCountLabel)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            if model.pendingPairs.isEmpty && model.sessions.isEmpty {
                Text("Waiting for Viewers to pair…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }

            ForEach(model.pendingPairs) { pending in
                VStack(alignment: .leading, spacing: 8) {
                    Text(pending.remoteDescription)
                        .font(.subheadline.weight(.semibold))

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Code")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))

                        Text(pending.code)
                            .font(.title3.monospacedDigit().weight(.bold))
                    }

                    HStack(spacing: 12) {
                        Button(role: .cancel) {
                            model.decline(pending.id)
                        } label: {
                            Text("Decline")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderless)
                        .tint(.white)

                        Spacer()

                        Button {
                            model.accept(pending.id)
                        } label: {
                            Text("Pair viewer")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .foregroundColor(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Accept pairing with \(pending.remoteDescription)")
                    }
                }
                .padding(.top, 4)
            }

            if !model.sessions.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.3))

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
                            .foregroundStyle(.white)
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.95),
                            Color.accentColor.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
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

    private var statusSummary: some View {
        HStack(spacing: 8) {
            Label(
                model.started ? "Hosting" : "Not hosting",
                systemImage: model.started ? "wifi.router.fill" : "wifi.slash"
            )

            Label(viewerCountLabel, systemImage: "person.2")

            Label(
                model.broadcastOn ? "Broadcast ON" : "Broadcast OFF",
                systemImage: model.broadcastOn ? "dot.radiowaves.left.right" : "wave.3.right"
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// Called by the big quick‑start button.
    /// Ensures the server is running, then taps the hidden Broadcast picker.
    private func startQuickShare() {
        if !model.started {
            model.toggleServer()
        }

        broadcastController.startBroadcast()
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
/// The big SwiftUI button calls `startBroadcast()` which taps it.
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
