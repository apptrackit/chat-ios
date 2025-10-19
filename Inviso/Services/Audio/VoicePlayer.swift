//
//  VoicePlayer.swift
//  Inviso
//
//  Handles voice message playback.
//

import Foundation
import AVFoundation
import Combine

@MainActor
class VoicePlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackProgress: Double = 0 // 0 to 1
    
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    
    override init() {
        super.init()
    }
    
    /// Load audio file
    func load(url: URL) throws {
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()
        duration = audioPlayer?.duration ?? 0
    }
    
    /// Play audio
    func play() {
        // Setup audio session for playback
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .default)
        try? audioSession.setActive(true)
        
        audioPlayer?.play()
        isPlaying = true
        
        // Start progress timer
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentTime = self.audioPlayer?.currentTime ?? 0
                if self.duration > 0 {
                    self.playbackProgress = self.currentTime / self.duration
                }
            }
        }
    }
    
    /// Pause audio
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    /// Stop audio and reset
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        playbackProgress = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    /// Seek to position (0 to 1)
    func seek(to progress: Double) {
        let time = duration * progress
        audioPlayer?.currentTime = time
        currentTime = time
        playbackProgress = progress
    }
    
    deinit {
        playbackTimer?.invalidate()
    }
}

// MARK: - AVAudioPlayerDelegate
extension VoicePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            stop()
        }
    }
}
