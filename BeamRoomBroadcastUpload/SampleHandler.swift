//
//  SampleHandler.swift
//  BeamRoomBroadcastUpload
//
//  Created by . . on 9/21/25.
//

// BeamRoomBroadcastUpload/SampleHandler.swift
//
// Minimal glue to turn ReplayKit samples into H.264 (via H264Encoder)
// and push them over UDP using UDPMediaSender. Broadcast ON/OFF is mirrored
// in the App Group via BeamConfig so the Host UI and Viewer can reflect it.
//

import ReplayKit
import BeamCore

final class SampleHandler: RPBroadcastSampleHandler {

    private var encoder: H264Encoder?

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        BeamConfig.setBroadcast(on: true)
        Task { await UDPMediaSender.shared.start() }
        encoder = H264Encoder()
    }

    override func broadcastFinished() {
        BeamConfig.setBroadcast(on: false)
        Task { await UDPMediaSender.shared.stop() }
        encoder?.invalidate()
        encoder = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, let encoder else { return }

        // IMPORTANT: we pass a @Sendable closure but DO NOT send CMSampleBuffer across actors.
        encoder.encode(sampleBuffer) { @Sendable encoded in
            // Convert to sendable primitives on the caller thread.
            guard let avcc = H264Encoder.avccData(from: encoded.sample) else { return }
            let w = encoded.width
            let h = encoded.height
            let ps = encoded.paramSets
            let isKey = encoded.isKeyframe

            // Now hop to the actor with only Data + Ints (Sendable-safe).
            Task {
                await UDPMediaSender.shared.sendAVCC(
                    width: w,
                    height: h,
                    avcc: avcc,
                    paramSets: ps,
                    isKeyframe: isKey
                )
            }
        }
    }
}
