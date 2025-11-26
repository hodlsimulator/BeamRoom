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
            .sink { [weak self] in self?.sessions = $0 }
            .store(in: &cancellables)

        server.$pendingPairs
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.pendingPairs = $0 }
            .store(in: &cancellables)

        server.$udpPeer
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.udpPeer = $0 }
            .store(in: &cancellables)
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
            HStack {
                Text("Broadcast status")
                Spacer()
                Circle()
                    .fill(model.broadcastOn ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(model.broadcastOn ? "ON" : "OFF")
                    .foregroundColor(model.broadcastOn ? .green : .secondary)
                    .font(.subheadline.bold())
            }

            VStack(alignment: .leading, spacing: 10) {
                // Hidden system picker – this is what actually talks to ReplayKit
                BroadcastPickerShim(controller: broadcastController)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)

                Button {
                    broadcastController.startBroadcast()
                } label: {
                    Label("Start Screen Broadcast", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text(
                    "If the sheet doesn’t appear, open Control Centre, long-press Screen Recording, choose “BeamRoom Upload2”, then tap Start Broadcast."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Text("Once broadcasting, video is sent to paired Viewers even while this app is in the background.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Screen broadcast")
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

        // Let the system show all upload extensions; user picks BeamRoomUpload2.
        picker.preferredExtension = nil

        controller.pickerView = picker
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        controller.pickerView = uiView
    }
}
