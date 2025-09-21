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

final class SampleHandler: RPBroadcastSampleHandler {

    private let log = Logger(subsystem: BeamConfig.subsystemExt, category: "upload")

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        log.info("Broadcast started. Setup: \(String(describing: setupInfo), privacy: .public)")
        // M0: no transport initialized yet.
    }

    override func broadcastPaused() {
        log.info("Broadcast paused")
    }

    override func broadcastResumed() {
        log.info("Broadcast resumed")
    }

    override func broadcastFinished() {
        log.info("Broadcast finished")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // M0: Drop everything (no-op) — will wire in VTCompression + UDP at M4.
        switch sampleBufferType {
        case .video: break
        case .audioApp: break
        case .audioMic: break
        @unknown default: break
        }
    }
}
