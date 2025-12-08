//
//  ViewerRootView+BottomBar.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI

extension ViewerRootView {
    // MARK: Bottom controls (pinned)

    var bottomControlsCard: some View {
        HStack(spacing: 12) {
            awarePickButton()
            Spacer()
            connectionStatus
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.20),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.7),
                                    Color.white.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                )
        )
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
    }

    @ViewBuilder
    func awarePickButton() -> some View {
        Button {
            model.showAwareSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .imageScale(.medium)
                Text("Nearby pairing")
                    .font(.footnote.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var connectionStatus: some View {
        switch model.client.status {
        case .idle:
            EmptyView()

        case .connecting(let hostName, _):
            Label("Connecting to \(hostName)…", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))

        case .waitingAcceptance:
            Label("Waiting for Host…", systemImage: "hourglass")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))

        case .paired:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.green)

        case .failed:
            Label("Connection failed", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }
}
