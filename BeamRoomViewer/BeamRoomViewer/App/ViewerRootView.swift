//
//  ViewerRootView.swift
//  BeamRoomViewer
//
//  Created by . . on 9/21/25.
//
//  M1 UI — discovers Hosts via Bonjour/Wi-Fi Aware,
//  lets user tap a Host to pair with a 4-digit code.
//

import SwiftUI
import Combine
import BeamCore
import Network

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var code: String = BeamControlClient.randomCode()
    @Published var selectedHost: DiscoveredHost?
    @Published var showPairSheet: Bool = false

    let browser = BeamBrowser()
    let client = BeamControlClient()

    func startDiscovery() {
        do { try browser.start() } catch { }
    }

    func stopDiscovery() {
        browser.stop()
    }

    func pick(_ host: DiscoveredHost) {
        selectedHost = host
        code = BeamControlClient.randomCode()
        client.connect(to: host, code: code)
        showPairSheet = true
    }

    func cancelPairing() {
        client.disconnect()
        showPairSheet = false
    }
}

struct ViewerRootView: View {
    @StateObject private var model = ViewerViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("BeamRoom — Viewer")
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)

                if model.browser.hosts.isEmpty {
                    VStack(spacing: 8) {
                        Text("Discovering nearby Hosts…")
                            .font(.headline)
                        ProgressView()
                    }
                } else {
                    List(model.browser.hosts) { host in
                        Button {
                            model.pick(host)
                        } label: {
                            HStack {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                Text(host.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .frame(maxHeight: 320)
                }

                Spacer(minLength: 12)
                Text(BeamCore.hello())
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Viewer")
            .task { model.startDiscovery() }
            .onDisappear { model.stopDiscovery() }
            .sheet(isPresented: $model.showPairSheet) {
                PairSheet(model: model)
            }
        }
    }
}

private struct PairSheet: View {
    @ObservedObject var model: ViewerViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let host = model.selectedHost {
                    Text("Pairing with")
                        .font(.headline)
                    Text(host.name)
                        .font(.title3).bold()
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                Text("Your code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.code)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()

                switch model.client.status {
                case .idle:
                    Text("Idle").foregroundStyle(.secondary)
                case .connecting(let hostName, _):
                    Label("Connecting to \(hostName)…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                case .waitingAcceptance:
                    Label("Waiting for Host to accept…", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                case .paired(let sid, _):
                    Label("Paired ✓", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Session: \(sid.uuidString)")
                        .font(.footnote).monospaced()
                        .foregroundStyle(.secondary)
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
                    }
                }
            }
            .padding()
            .navigationTitle("Pair")
            .presentationDetents([.medium])
        }
    }
}

#Preview {
    ViewerRootView()
}
