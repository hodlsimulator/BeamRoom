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

    private var cancellables: Set<AnyCancellable> = []
    private var broadcastPoll: DispatchSourceTimer?

    init() {
        // Default to auto‑accept so the common “one Host + one Viewer”
        // flow works without extra approval taps.
        let auto = true

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
    @StateObject var model = HostViewModel()
    @StateObject var broadcastController = BroadcastLaunchController()

    @State private var showingAbout = false
    @State var showingBroadcastHelp = false

    var body: some View {
        NavigationStack {
            ZStack {
                liquidBackground

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        heroCard
                        hostSettingsCard
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .padding(.bottom, 44) // space above pinned pairing card
                }
            }
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
        // Keep the whole screen dark-styled, so the title is white even in system light mode.
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .confirmationDialog(
            "Screen broadcast help",
            isPresented: $showingBroadcastHelp,
            titleVisibility: .visible
        ) {
            Button {
                broadcastController.startBroadcast()
            } label: {
                Text("Open Screen Broadcast controls")
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }

            Button(role: .cancel) {
                // no extra action needed
            } label: {
                Text("Cancel")
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
        } message: {
            Text(
                """
                If the sheet does not appear, open Control Centre, long‑press Screen Recording, choose “BeamRoom”, then tap Start Broadcast.
                Once broadcasting, video is sent to paired Viewers even while this app is in the background.
                """
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
