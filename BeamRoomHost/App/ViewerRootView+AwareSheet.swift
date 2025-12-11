//
//  ViewerRootView+AwareSheet.swift
//  BeamRoomHost
//
//  Created by . . on 12/8/25.
//

import SwiftUI
import BeamCore

#if canImport(DeviceDiscoveryUI)
import DeviceDiscoveryUI
#endif

#if canImport(WiFiAware)
import WiFiAware
#endif

extension ViewerRootView {

    // MARK: Wi‑Fi Aware sheet

    @ViewBuilder
    func awarePickSheet() -> some View {
        #if canImport(DeviceDiscoveryUI) && canImport(WiFiAware)
        if let service = AwareSupport.subscriberService(named: BeamConfig.controlService) {
            let devices: WASubscriberBrowser.Devices = .userSpecifiedDevices
            let provider = WASubscriberBrowser.wifiAware(
                .connecting(to: devices, from: service),
                active: nil
            )

            DevicePicker(
                provider,
                onSelect: { _ in
                    BeamLog.info("Aware picker selection", tag: "viewer")
                    model.showAwareSheet = false
                },
                label: {
                    Text("Pair Viewer")
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                },
                fallback: {
                    AwareUnavailableView(
                        model: model,
                        message: "Wi‑Fi Aware not available."
                    )
                }
            )
        } else {
            AwareUnavailableView(
                model: model,
                message: "Wi‑Fi Aware service not available."
            )
        }
        #else
        AwareUnavailableView(
            model: model,
            message: "Wi‑Fi Aware UI is not available on this build configuration."
        )
        #endif
    }
}

// MARK: - Fallback view (auto‑dismisses)

private struct AwareUnavailableView: View {
    @ObservedObject var model: ViewerViewModel
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)

            // Button remains for clarity, but auto‑dismiss handles the common case.
            Button("Close") {
                model.showAwareSheet = false
            }
            .lineLimit(1)
            .minimumScaleFactor(0.9)
        }
        .padding()
        .onAppear {
            // Automatically collapse the expanded pairing UI so the stream
            // can start without an extra Close tap.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if model.showAwareSheet {
                    model.showAwareSheet = false
                }
            }
        }
    }
}
