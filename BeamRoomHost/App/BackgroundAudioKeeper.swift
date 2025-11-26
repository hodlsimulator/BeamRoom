//
//  BackgroundAudioKeeper.swift
//  BeamRoomHost
//
//  Created by . . on 11/25/25.
//
//  Keeps the host process alive while a ReplayKit broadcast is running
//  by looping a tiny block of silence in an AVAudioEngine.
//

import Foundation
import AVFoundation
import OSLog

final class BackgroundAudioKeeper {
    static let shared = BackgroundAudioKeeper()

    private let log = Logger(subsystem: "BeamRoomHost", category: "bg-audio")

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
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            log.error("AVAudioSession setup failed: \(error.localizedDescription)")
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
                ptr.update(repeating: 0, count: samplesPerChannel)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            player.play()
            isRunning = true
            log.notice("Background audio keeper started")
        } catch {
            log.error("Audio engine start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRunning else { return }

        player.stop()
        engine.stop()
        isRunning = false

        do {
            try AVAudioSession.sharedInstance()
                .setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            log.error("AVAudioSession deactivate failed: \(error.localizedDescription)")
        }

        log.notice("Background audio keeper stopped")
    }
}
