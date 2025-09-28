//
//  SampleHandler.swift
//  BeamRoomUpload2
//
//  Created by . . on 9/28/25.
//

import ReplayKit
import BeamCore

final class SampleHandler: RPBroadcastSampleHandler {
    private var encoder: H264Encoder?

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        // Mark ON for Host/Viewer UI and start UDP sender
        BeamConfig.setBroadcast(on: true)
        Task { await UDPMediaSender.shared.start() }
        encoder = H264Encoder()
    }

    override func broadcastPaused() {
        // Optional: nothing to do (we just stop receiving samples)
    }

    override func broadcastResumed() {
        // Optional: nothing to do
    }

    override func broadcastFinished() {
        // Mark OFF and tear down encoder/sender
        BeamConfig.setBroadcast(on: false)
        Task { await UDPMediaSender.shared.stop() }
        encoder?.invalidate()
        encoder = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, let encoder else { return }

        // Encode on the calling thread; the callback gives us a CMSampleBuffer we immediately
        // convert to Sendable primitives before hopping to the actor.
        encoder.encode(sampleBuffer) { @Sendable encoded in
            guard let avcc = H264Encoder.avccData(from: encoded.sample) else { return }
            let w = encoded.width
            let h = encoded.height
            let ps = encoded.paramSets
            let isKey = encoded.isKeyframe

            Task {
                await UDPMediaSender.shared.sendAVCC(
                    width: w, height: h,
                    avcc: avcc,
                    paramSets: ps,
                    isKeyframe: isKey
                )
            }
        }
    }
}
