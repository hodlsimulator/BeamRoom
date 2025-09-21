//
//  HostRootView.swift
//  BeamRoomHost
//
//  Created by . . on 9/21/25.
//
//  M1 UI — publishes control service, shows incoming pair requests,
//  and lets the user Accept / Decline.
//

import SwiftUI
import Combine
import BeamCore
import UIKit

@MainActor
final class HostViewModel: ObservableObject {
    @Published var serviceName: String = UIDevice.current.name
    @Published var started: Bool = false
    let server = BeamControlServer()

    func toggle() {
        if started {
            server.stop()
            started = false
        } else {
            do { try server.start(serviceName: serviceName); started = true }
            catch { started = false }
        }
    }

    func accept(_ id: UUID) { server.accept(id) }
    func decline(_ id: UUID) { server.decline(id) }
}

struct HostRootView: View {
    @StateObject private var model = HostViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("BeamRoom — Host").font(.largeTitle).bold().multilineTextAlignment(.center)

                HStack {
                    TextField("Service Name", text: $model.serviceName)
                        .textFieldStyle(.roundedBorder)
                    Button(model.started ? "Stop" : "Publish") { model.toggle() }
                        .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().frame(width: 10, height: 10)
                            .foregroundStyle(model.started ? .green : .secondary)
                        Text(model.started
                             ? "Advertising \(model.serviceName) on \(BeamConfig.controlService)"
                             : "Not advertising")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }

                    if !model.server.sessions.isEmpty {
                        Text("Active Sessions").font(.headline)
                        List(model.server.sessions) { s in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(s.id.uuidString).font(.footnote).monospaced()
                                    Text(s.remoteDescription).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(s.startedAt, style: .time).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .listStyle(.plain).frame(maxHeight: 180)
                    }

                    Text("Pair Requests").font(.headline)
                    if model.server.pendingPairs.isEmpty {
                        Text("None yet.\nA Viewer will tap your name and send a 4-digit code.")
                            .font(.callout).foregroundStyle(.secondary)
                    }

                    List(model.server.pendingPairs) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Code: \(p.code)").font(.title2).bold().monospaced()
                                Text(p.remoteDescription).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Button("Decline") { model.decline(p.id) }.buttonStyle(.bordered)
                                Button("Accept") { model.accept(p.id) }.buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain).frame(minHeight: 120, maxHeight: 240)
                }

                Spacer(minLength: 12)
                Text(BeamCore.hello()).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Host")
            .task { if !model.started { model.toggle() } } // auto-publish once
        }
    }
}

#Preview { HostRootView() }
