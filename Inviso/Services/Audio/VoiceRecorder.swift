//
//  VoiceRecorder.swift
//  Inviso
//
//  Manages voice recording with AVAudioRecorder.
//

import Foundation
import AVFoundation
import Combine

@MainActor
class VoiceRecorder: NSObject, ObservableObject {
    // Published properties
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingLevel: Float = 0 // For waveform visualization
    @Published var hasPermission = false
    @Published var error: RecordingError?
    
    // Internal properties
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var levelTimer: Timer?
    private var currentRecordingURL: URL?
    
    enum RecordingError: LocalizedError {
        case permissionDenied
        case recordingFailed
        case audioSessionFailed
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone access denied. Please enable it in Settings."
            case .recordingFailed:
                return "Failed to record audio. Please try again."
            case .audioSessionFailed:
                return "Audio session error. Please check your device settings."
            }
        }
    }
    
    override init() {
        super.init()
        checkPermission()
    }
    
    /// Check microphone permission
    func checkPermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            hasPermission = true
        case .denied:
            hasPermission = false
        case .undetermined:
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }
    
    /// Request microphone permission
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in
                    self.hasPermission = granted
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    /// Start recording
    func startRecording() async throws -> URL {
        // Check permission
        if !hasPermission {
            let granted = await requestPermission()
            if !granted {
                throw RecordingError.permissionDenied
            }
        }
        
        // Setup audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            throw RecordingError.audioSessionFailed
        }
        
        // Create temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "voice_\(UUID().uuidString).m4a"
        let fileURL = tempDir.appendingPathComponent(filename)
        currentRecordingURL = fileURL
        
        // Recording settings (optimized for voice)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 64000
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            
            isRecording = true
            recordingDuration = 0
            
            // Start duration timer
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.recordingDuration = self.audioRecorder?.currentTime ?? 0
                }
            }
            
            // Start level monitoring timer
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.audioRecorder?.updateMeters()
                    let power = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
                    // Normalize power to 0-1 range (-160 to 0 dB)
                    let normalized = max(0, min(1, (power + 160) / 160))
                    self.recordingLevel = normalized
                }
            }
            
            return fileURL
        } catch {
            throw RecordingError.recordingFailed
        }
    }
    
    /// Stop recording
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        isRecording = false
        recordingTimer?.invalidate()
        levelTimer?.invalidate()
        recordingTimer = nil
        levelTimer = nil
        recordingLevel = 0
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
        
        return currentRecordingURL
    }
    
    /// Cancel recording and delete file
    func cancelRecording() {
        if let url = stopRecording() {
            try? FileManager.default.removeItem(at: url)
            currentRecordingURL = nil
        }
        recordingDuration = 0
    }
    
    /// Reset state
    func reset() {
        recordingDuration = 0
        recordingLevel = 0
        currentRecordingURL = nil
        error = nil
    }
}

// MARK: - AVAudioRecorderDelegate
extension VoiceRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                error = .recordingFailed
            }
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.error = .recordingFailed
        }
    }
}
