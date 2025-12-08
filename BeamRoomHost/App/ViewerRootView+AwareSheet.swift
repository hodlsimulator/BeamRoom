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
                },
                fallback: {
                    VStack(spacing: 12) {
                        Text("Wi‑Fi Aware not available.")
                        Button("Close") {
                            model.showAwareSheet = false
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    }
                    .padding()
                }
            )
        } else {
            VStack(spacing: 12) {
                Text("Wi‑Fi Aware service not available.")
                Button("Close") {
                    model.showAwareSheet = false
                }
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            }
            .padding()
        }
        #else
        VStack(spacing: 12) {
            Text("Wi‑Fi Aware UI is not available on this build configuration.")
            Button("Close") {
                model.showAwareSheet = false
            }
            .lineLimit(1)
            .minimumScaleFactor(0.9)
        }
        .padding()
        #endif
    }
}
