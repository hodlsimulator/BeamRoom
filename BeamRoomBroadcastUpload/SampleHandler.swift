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
        log.info("Broadcast started. Setup: \(String(describing: setupInfo))")
        BeamConfig.setBroadcast(on: true) // M2: flip shared flag
        // M3: initialise VTCompression + UDP media here.
    }

    override func broadcastPaused() {
        log.info("Broadcast paused")
    }

    override func broadcastResumed() {
        log.info("Broadcast resumed")
    }

    override func broadcastFinished() {
        log.info("Broadcast finished")
        BeamConfig.setBroadcast(on: false) // M2: clear flag
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // M2: Drop everything (no-op). M3 will packetise and send.
        switch sampleBufferType {
        case .video: break
        case .audioApp: break
        case .audioMic: break
        @unknown default: break
        }
    }
}
