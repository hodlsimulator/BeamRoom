//
//  SampleHandler.swift
//  BeamRoomUpload2
//
//  Created by . . on 9/28/25.
//

import ReplayKit
import OSLog
import BeamCore

@objc(SampleHandler)
final class SampleHandler: RPBroadcastSampleHandler {

    private let log = Logger(subsystem: BeamConfig.subsystemExt, category: "upload2")
    private let encoder = H264Encoder()

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        BeamConfig.setBroadcast(on: true)
        Task { await UDPMediaSender.shared.start() }
        log.notice("Broadcast started")
    }

    override func broadcastFinished() {
        BeamConfig.setBroadcast(on: false)
        encoder.stop()
        Task { await UDPMediaSender.shared.stop() }
        log.notice("Broadcast finished")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        encoder.encode(sampleBuffer: sampleBuffer) { frame in
            if frame.avcc.isEmpty { return }
            Task {
                await UDPMediaSender.shared.sendAVCC(
                    width: frame.width,
                    height: frame.height,
                    avcc: frame.avcc,
                    paramSets: frame.paramSets,
                    isKeyframe: frame.isKeyframe
                )
            }
        }
    }
}
