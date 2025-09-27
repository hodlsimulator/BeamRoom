//
//  HostRootView.swift
//  BeamRoomHost
//
//  Created by . . on 9/21/25.
//
//  Test Stream UI removed. Host now focuses on advertising + Broadcast picker.
//  MediaUDP still runs (for UDP port + peer bridging), but there’s no fake-frame button.
//

import SwiftUI
import Combine
import BeamCore
import UIKit
import Network
import ReplayKit

@MainActor
final class HostViewModel: ObservableObject {
    @Published var serviceName: String = UIDevice.current.name
    @Published var started: Bool = false
    @Published var autoAccept: Bool = BeamConfig.autoAcceptDuringTest
    @Published var broadcastOn: Bool = BeamConfig.isBroadcastOn() // mirror App Group flag
    @Published var sessions: [BeamControlServer.ActiveSession] = []
    @Published var pendingPairs: [BeamControlServer.PendingPair] = []
    @Published var udpPeer: String? = nil

    let server: BeamControlServer
    private var pollTimer: DispatchSourceTimer?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.server = BeamControlServer(autoAccept: BeamConfig.autoAcceptDuringTest)
        // Bridge server → view model
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

    func toggle() {
        if started {
            server.stop()
            stopBroadcastPoll()
            started = false
        } else {
            do {
                try server.start(serviceName: serviceName)
                startBroadcastPoll()
                started = true
            } catch {
                started = false
                BeamLog.error("Start error: \(error.localizedDescription)", tag: "host")
            }
        }
    }

    func setAutoAccept(_ v: Bool) { server.autoAccept = v }
    func accept(_ pendingID: UUID) { server.accept(pendingID) }
    func decline(_ pendingID: UUID) { server.decline(pendingID) }

    // MARK: Broadcast poll (App Group flag → UI)
    private func startBroadcastPoll() {
        stopBroadcastPoll()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let on = BeamConfig.isBroadcastOn()
            Task { @MainActor in
                if on != self.broadcastOn { self.broadcastOn = on }
            }
        }
        t.resume()
        pollTimer = t
    }

    private func stopBroadcastPoll() { pollTimer?.cancel(); pollTimer = nil }
}

struct HostRootView: View {
    @StateObject private var model = HostViewModel()
    @State private var showLogs = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("BeamRoom — Host")
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)

                HStack {
                    TextField("Service Name", text: $model.serviceName)
                        .textFieldStyle(.roundedBorder)
                    Button(model.started ? "Stop" : "Publish") { model.toggle() }
                        .buttonStyle(.borderedProminent)
                        .lineLimit(1).minimumScaleFactor(0.9)
                }

                Toggle("Auto-accept Viewer PINs (testing)", isOn: $model.autoAccept)
                    .onChange(of: model.autoAccept) { _, new in model.setAutoAccept(new) }

                // Broadcast controls (ReplayKit system picker)
                broadcastSection

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().frame(width: 10, height: 10)
                            .foregroundStyle(model.started ? .green : .secondary)
                        Text(model.started
                             ? "Advertising \(model.serviceName) on \(BeamConfig.controlService)"
                             : "Not advertising")
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                    }

                    if !model.sessions.isEmpty {
                        Text("Active Sessions").font(.headline)
                        List(model.sessions) { s in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(s.id.uuidString)
                                        .font(.footnote).monospaced().lineLimit(1).minimumScaleFactor(0.7)
                                    Text(s.remoteDescription)
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(s.startedAt, style: .time)
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .listStyle(.plain).frame(maxHeight: 180)
                    }

                    Text("Pair Requests").font(.headline)
                    if model.pendingPairs.isEmpty {
                        Text("None yet.\nA Viewer will tap your name and send a 4-digit code.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        List(model.pendingPairs) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Code: \(p.code)")
                                        .font(.title2).bold().monospaced().lineLimit(1)
                                    Text("conn#\(p.connID) • \(p.remoteDescription)")
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    Button("Decline") { model.decline(p.id) }
                                        .buttonStyle(.bordered)
                                    Button("Accept") { model.accept(p.id) }
                                        .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listStyle(.plain).frame(minHeight: 120, maxHeight: 240)
                    }
                }

                Spacer(minLength: 12)
                Text(BeamCore.hello())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding()
            .navigationTitle("Host")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showLogs = true } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .lineLimit(1)
                }
            }
            .task {
                if !model.started { model.toggle() }
                model.setAutoAccept(model.autoAccept)
            }
            .sheet(isPresented: $showLogs) { BeamLogView() }
        }
    }

    // MARK: Broadcast UI
    @ViewBuilder private var broadcastSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(model.broadcastOn ? "Broadcast: On" : "Broadcast: Off",
                      systemImage: model.broadcastOn ? "dot.radiowaves.left.right" : "wave.3.right")
                    .foregroundStyle(model.broadcastOn ? .green : .secondary)
                    .font(.headline)
                Spacer()
            }
            BroadcastPicker().frame(height: 44) // system Start/Stop button
            HStack(spacing: 6) {
                Text("Active Viewer UDP peer:").foregroundStyle(.secondary)
                Text(model.udpPeer ?? "none")
                    .font(.caption).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}

// RPSystemBroadcastPickerView wrapper: auto-detects the Upload extension.
private struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView()
        v.showsMicrophoneButton = false
        v.preferredExtension = Self.findUploadExtensionBundleID()
        return v
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}

    private static func findUploadExtensionBundleID() -> String? {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return nil }
        let fm = FileManager.default
        guard let it = fm.enumerator(at: plugins, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in it {
            if url.pathExtension == "appex",
               let b = Bundle(url: url),
               let info = b.infoDictionary,
               let ext = info["NSExtension"] as? [String: Any],
               let point = ext["NSExtensionPointIdentifier"] as? String,
               point == "com.apple.broadcast-services-upload" {
                return b.bundleIdentifier
            }
        }
        return nil
    }
}
