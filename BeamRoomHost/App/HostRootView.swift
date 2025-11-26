//
//  HostRootView.swift
//  BeamRoomHost
//
//  Created by . . on 9/21/25.
//

import SwiftUI
import Combine
import BeamCore
import OSLog
import ReplayKit

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

    private var cancellables: Set<AnyCancellable> = []
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
    }

    // MARK: - Public API for the view

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

    // MARK: - Broadcast polling → drives UI + background audio

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

// MARK: - View

struct HostRootView: View {
    @StateObject private var model = HostViewModel()
    @State private var showingLogs = false

    var body: some View {
        NavigationStack {
            List {
                hostSection
                broadcastSection
                pairingSection
            }
            .navigationTitle("BeamRoom Host")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingLogs = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .accessibilityLabel("Show logs")
                }
            }
        }
        .sheet(isPresented: $showingLogs) {
            NavigationStack {
                BeamLogView()
                    .navigationTitle("Logs")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showingLogs = false
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Sections

    private var hostSection: some View {
        Section {
            TextField("Service name", text: $model.serviceName)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            Button {
                model.toggleServer()
            } label: {
                Label(
                    model.started ? "Stop hosting" : "Start hosting",
                    systemImage: model.started ? "stop.circle.fill" : "play.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)

            Toggle(
                "Auto-accept pairing",
                isOn: Binding(
                    get: { model.autoAccept },
                    set: { model.setAutoAccept($0) }
                )
            )

            if let peer = model.udpPeer {
                Label("UDP peer: \(peer)", systemImage: "dot.radiowaves.left.and.right")
            } else {
                Label("UDP peer: none", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Host")
        }
    }

    private var broadcastSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(model.broadcastOn ? "ON" : "OFF")
                        .foregroundStyle(model.broadcastOn ? .green : .secondary)
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }

                Text(
                    model.broadcastOn
                    ? "Screen sharing is live. You can switch to any app and this host will stay awake in the background while broadcasting."
                    : "To share the screen, start a ReplayKit broadcast. Use the button below, or long-press Screen Recording in Control Centre and choose BeamRoom."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        BroadcastPicker()
                            .frame(width: 220, height: 52)
                            .accessibilityLabel("Start or stop screen broadcast")

                        Text("Tap to start / stop")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        } header: {
            Text("Screen broadcast")
        } footer: {
            Text("Tip: If the button above does not appear, open Control Centre, long-press Screen Recording and pick “BeamRoom” from the list.")
                .font(.caption2)
        }
    }

    private var pairingSection: some View {
        Section {
            if model.pendingPairs.isEmpty && model.sessions.isEmpty {
                Text("No active or pending viewers.")
                    .foregroundStyle(.secondary)
            }

            ForEach(model.pendingPairs) { pending in
                HStack {
                    VStack(alignment: .leading) {
                        Text(pending.remoteDescription)

                        Text("Code \(pending.code)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Decline") {
                        model.decline(pending.id)
                    }
                    .buttonStyle(.bordered)

                    Button("Accept") {
                        model.accept(pending.id)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            ForEach(model.sessions) { session in
                VStack(alignment: .leading) {
                    Text(session.remoteDescription)

                    Text("Connected \(session.startedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Pairing")
        }
    }
}

// MARK: - Broadcast picker

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView()
        view.showsMicrophoneButton = false
        // If you want to force the specific extension, set preferredExtension here:
        // view.preferredExtension = "com.yourcompany.BeamRoomUpload2"
        return view
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        // No-op
    }
}
