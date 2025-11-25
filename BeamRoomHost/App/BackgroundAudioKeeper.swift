//
//  BackgroundAudioKeeper.swift
//  BeamRoomHost
//
//  Created by . . on 11/25/25.
//

import Foundation
import AVFoundation
import OSLog

final class BackgroundAudioKeeper {
    static let shared = BackgroundAudioKeeper()

    private let log = Logger(subsystem: BeamConfig.subsystemHost, category: "bg-audio")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isRunning = false

    private init() {
        engine.attach(player)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() {
        guard !isRunning else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            log.error("AVAudioSession setup failed: \(error.localizedDescription, privacy: .public)")
        }

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let frameCount: AVAudioFrameCount = 1024

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            log.error("Failed to create audio buffer")
            return
        }

        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            let channels = Int(format.channelCount)
            let samplesPerChannel = Int(frameCount)
            for channel in 0..<channels {
                let ptr = channelData[channel]
                ptr.initialize(repeating: 0, count: samplesPerChannel)
            }
        }

        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)

        do {
            try engine.start()
            player.play()
            isRunning = true
            log.info("Background audio engine started")
        } catch {
            log.error("Audio engine start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        guard isRunning else { return }

        player.stop()
        engine.stop()
        isRunning = false
        log.info("Background audio engine stopped")

        do {
            try AVAudioSession.sharedInstance().setActive(false,
                                                         options: [.notifyOthersOnDeactivation])
        } catch {
            log.error("AVAudioSession deactivate failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
