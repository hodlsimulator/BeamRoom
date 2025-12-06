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
import BeamCore

@MainActor
final class BackgroundAudioKeeper {

    static let shared = BackgroundAudioKeeper()

    private let log = Logger(subsystem: BeamConfig.subsystemHost, category: "bg-audio")

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private var isRunning = false
    private var silenceBuffer: AVAudioPCMBuffer?

    private init() {
        setUpEngine()

        let centre = NotificationCenter.default
        centre.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        centre.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    func start() {
        // Idempotent. If we're already meant to be running, just make
        // sure the engine is up (useful after an interruption).
        if isRunning {
            startEngineIfNeeded()
            return
        }

        isRunning = true
        log.info("Background audio START")

        configureSession()
        prepareSilenceBufferIfNeeded()
        startEngineIfNeeded()
    }

    func stop() {
        guard isRunning else { return }

        isRunning = false
        log.info("Background audio STOP")

        player.stop()
        engine.stop()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            log.error("AVAudioSession deactivate failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Engine / Session

    private func setUpEngine() {
        engine.attach(player)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            log.error("AVAudioSession setup failed: \(error.localizedDescription)")
        }
    }

    private func prepareSilenceBufferIfNeeded() {
        if silenceBuffer != nil { return }

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let frameCount: AVAudioFrameCount = 1024

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            log.error("Failed to create AVAudioPCMBuffer for background audio")
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
            do {
                try engine.start()
                log.info("AVAudioEngine started")
            } catch {
                log.error("AVAudioEngine start failed: \(error.localizedDescription)")
                return
            }
        }

        guard let buffer = silenceBuffer else {
            log.error("No silence buffer available when starting engine")
            return
        }

        if !player.isPlaying {
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
            player.play()
            log.debug("Background audio player now looping silence")
        }
    }

    // MARK: - Notifications

    @objc
    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            log.info("AVAudioSession interruption began")
            if engine.isRunning {
                engine.pause()
            }
            player.stop()

        case .ended:
            log.info("AVAudioSession interruption ended")

            guard isRunning else { return }

            // Even if the system does not give us a `.shouldResume` hint,
            // the whole purpose here is to keep the Host alive whenever
            // a Broadcast is running, so always try to come back.
            configureSession()
            prepareSilenceBufferIfNeeded()
            startEngineIfNeeded()

        @unknown default:
            break
        }
    }

    @objc
    private func handleRouteChange(_ notification: Notification) {
        guard isRunning else { return }

        log.debug("AVAudioSession route changed; ensuring engine is running")
        configureSession()
        prepareSilenceBufferIfNeeded()
        startEngineIfNeeded()
    }
}
