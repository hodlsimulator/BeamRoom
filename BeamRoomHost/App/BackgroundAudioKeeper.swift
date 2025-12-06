//
//  BackgroundAudioKeeper.swift
//  BeamRoomHost
//
//  Created by . . on 11/25/25.
//
//  Keeps the host process alive while a ReplayKit broadcast is running
//  by looping a tiny block of silence in an AVAudioEngine. This version
//  is hardened to survive AVAudioSession interruptions (e.g. phone calls).
//

import Foundation
import AVFoundation
import OSLog

final class BackgroundAudioKeeper {

    static let shared = BackgroundAudioKeeper()

    private let log = Logger(subsystem: "BeamRoomHost", category: "bg-audio")

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    // Logical “we want background audio” flag.
    private var isRunning = false

    // Silence buffer we loop while the broadcast is on.
    private var silenceBuffer: AVAudioPCMBuffer?

    private init() {
        setupEngine()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Start (or re-start) the background audio loop.
    func start() {
        // If we've already been asked to run, just make sure the engine
        // is actually running. This covers the case where a phone call
        // stopped the engine while `isRunning` was still true.
        if isRunning {
            startEngineIfNeeded()
            return
        }

        isRunning = true

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            log.error("AVAudioSession setup failed: \(error.localizedDescription, privacy: .public)")
        }

        prepareSilenceBufferIfNeeded()
        startEngineIfNeeded()

        log.info("Background audio keeper started")
    }

    /// Stop the background audio loop completely.
    func stop() {
        guard isRunning else { return }

        isRunning = false

        player.stop()
        engine.stop()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            log.error("AVAudioSession deactivate failed: \(error.localizedDescription, privacy: .public)")
        }

        log.info("Background audio keeper stopped")
    }

    // MARK: - Engine setup

    private func setupEngine() {
        engine.attach(player)

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    private func prepareSilenceBufferIfNeeded() {
        if silenceBuffer != nil { return }

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

        silenceBuffer = buffer
    }

    private func startEngineIfNeeded() {
        guard isRunning else { return }

        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
                log.info("AVAudioEngine started for background audio")
            } catch {
                log.error("AVAudioEngine start failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if !player.isPlaying {
            if let buffer = silenceBuffer {
                // Loop silence indefinitely.
                player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            }
            player.play()
            log.info("AVAudioPlayerNode playing silence for background keep‑alive")
        }
    }

    // MARK: - AVAudioSession notifications

    @objc
    private func handleInterruption(_ notification: Notification) {
        guard isRunning else { return }

        guard
            let userInfo = notification.userInfo,
            let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return
        }

        switch type {
        case .began:
            log.info("AVAudioSession interruption began (likely phone call)")
            // The system will stop the engine; we just wait for `.ended`.
        case .ended:
            log.info("AVAudioSession interruption ended – attempting to resume background audio")

            let session = AVAudioSession.sharedInstance()
            do {
                try session.setActive(true)
            } catch {
                log.error("Failed to reactivate AVAudioSession: \(error.localizedDescription, privacy: .public)")
            }

            prepareSilenceBufferIfNeeded()
            startEngineIfNeeded()

        @unknown default:
            break
        }
    }

    @objc
    private func handleRouteChange(_ notification: Notification) {
        guard isRunning else { return }

        // If the route change stopped the engine, bring it back up.
        if !engine.isRunning {
            log.info("AVAudioSession route change detected – restarting background engine")
            prepareSilenceBufferIfNeeded()
            startEngineIfNeeded()
        }
    }
}
