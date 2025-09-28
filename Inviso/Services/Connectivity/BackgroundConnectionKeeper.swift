//
//  BackgroundConnectionKeeper.swift
//  Inviso
//
//  Created by GitHub Copilot on 9/28/25.
//

import Foundation
import AVFoundation
import UIKit

/// Keeps the WebRTC data channel alive while the app is in the background by maintaining a silent
/// audio session. This leverages the background audio entitlement to prevent iOS from suspending the
/// process when a peer-to-peer session is active.
final class BackgroundConnectionKeeper {
    static let shared = BackgroundConnectionKeeper()

    private let queue = DispatchQueue(label: "app.inviso.background-keeper", qos: .userInitiated)
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayerNode?
    private var silentBuffer: AVAudioPCMBuffer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isMaintainingConnection = false
    private var audioSessionActive = false

    private init() {}

    /// Starts or stops the keep-alive mechanism depending on the `shouldMaintain` flag.
    func setActive(_ shouldMaintain: Bool) {
        if shouldMaintain {
            startIfNeeded()
        } else {
            stopIfNeeded()
        }
    }

    private func startIfNeeded() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isMaintainingConnection else { return }
            self.isMaintainingConnection = true
            self.beginBackgroundTask()
            self.configureAudioSession()
            self.startAudioEngine()
        }
    }

    private func stopIfNeeded() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isMaintainingConnection else { return }
            self.isMaintainingConnection = false
            self.stopAudioEngine()
            self.endBackgroundTask()
        }
    }

    private func beginBackgroundTask() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.backgroundTask == .invalid {
                self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "rtc.keepalive") { [weak self] in
                    self?.queue.async { self?.stopIfNeeded() }
                }
            }
        }
    }

    private func endBackgroundTask() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
            self.deactivateAudioSession()
        }
    }

    private func configureAudioSession() {
        guard !audioSessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            audioSessionActive = true
        } catch {
            audioSessionActive = false
        }
    }

    private func deactivateAudioSession() {
        guard audioSessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Intentionally ignore errors to avoid surfacing in production builds.
        }
        audioSessionActive = false
    }

    private func startAudioEngine() {
        if audioEngine != nil {
            restartExistingEngine()
            return
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1) else { return }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.0

        let frameCount = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        if let channels = buffer.floatChannelData {
            for channelIndex in 0..<Int(format.channelCount) {
                memset(channels[channelIndex], 0, Int(frameCount) * MemoryLayout<Float>.size)
            }
        }

        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        do {
            try engine.start()
            player.play()
            audioEngine = engine
            audioPlayer = player
            silentBuffer = buffer
        } catch {
            engine.stop()
            audioEngine = nil
            audioPlayer = nil
            silentBuffer = nil
        }
    }

    private func restartExistingEngine() {
        guard let engine = audioEngine else { return }
        guard let player = audioPlayer else { return }
        if engine.isRunning == false {
            do {
                try engine.start()
            } catch {
                engine.stop()
                audioEngine = nil
                audioPlayer = nil
                silentBuffer = nil
                return
            }
        }
        if player.isPlaying == false {
            if let buffer = silentBuffer {
                player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
            }
            player.play()
        }
    }

    private func stopAudioEngine() {
        audioPlayer?.stop()
        audioPlayer = nil
        audioEngine?.stop()
        audioEngine?.reset()
        audioEngine = nil
        silentBuffer = nil
    }
}
