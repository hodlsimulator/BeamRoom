//
//  PairSheet.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI
import UIKit
import BeamCore

struct PairSheet: View {
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
                    Label("Connecting to \(hostName)…", systemImage: "arrow.triangle.2.circlepath")
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
                        systemImage: model.client.broadcastOn ? "dot.radiowaves.left.right" : "wave.3.right"
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
