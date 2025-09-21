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
        // No privacy parameters needed here; we’re logging a simple string.
        log.info("Broadcast started. Setup: \(String(describing: setupInfo))")
        // M0: no transport initialised yet.
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

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        // M0: Drop everything (no-op) — wire VTCompression + UDP later.
        switch sampleBufferType {
        case .video: break
        case .audioApp: break
        case .audioMic: break
        @unknown default: break
        }
    }
}
