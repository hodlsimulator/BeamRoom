//
//  SampleHandler.swift
//  BeamRoomBroadcastUpload
//
//  Created by . . on 9/21/25.
//

import ReplayKit
import OSLog
import BeamCore
import CoreMedia
import Network

final class SampleHandler: RPBroadcastSampleHandler {
    private let log = Logger(subsystem: BeamConfig.subsystemExt, category: "upload")

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        log.info("Broadcast started. Setup: \(String(describing: setupInfo))")

        // Flip the shared flag so hosts/viewers learn about state changes.
        BeamConfig.setBroadcast(on: true)

        // (Optional) If your media pipeline needs a fixed source port for outbound UDP,
        // you can create an ephemeral UDP connection here to learn it. For now we leave
        // the host app’s UDP listener (started by BeamControlServer) as the canonical port.
        // Just make sure to start your VideoToolbox encoder and send to the viewer’s socket(s).
    }

    override func broadcastPaused() {
        log.info("Broadcast paused")
    }

    override func broadcastResumed() {
        log.info("Broadcast resumed")
    }

    override func broadcastFinished() {
        log.info("Broadcast finished")
        BeamConfig.setBroadcast(on: false)
        // If you had any transport state, tear it down here.
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // M2 baseline: drop everything. M3 will packetise and send.
        switch sampleBufferType {
        case .video:    break
        case .audioApp: break
        case .audioMic: break
        @unknown default: break
        }
    }
}
