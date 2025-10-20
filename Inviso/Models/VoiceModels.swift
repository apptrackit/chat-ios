//
//  VoiceModels.swift
//  Inviso
//
//  Models for voice message data.
//

import Foundation

/// Voice message data compatible with Android
struct VoiceData: Codable, Equatable {
    let type: String
    let duration: Double // seconds
    let waveform: [Float] // normalized levels for visualization
    let audioData: String // base64 encoded audio (m4a)
    let timestamp: Int64 // Unix timestamp in milliseconds
    
    init(duration: Double, waveform: [Float], audioData: Data, timestamp: Date = Date()) {
        self.type = "voice"
        self.duration = duration
        self.waveform = waveform
        self.audioData = audioData.base64EncodedString()
        self.timestamp = Int64(timestamp.timeIntervalSince1970 * 1000)
    }
    
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
    }
    
    var decodedAudioData: Data? {
        Data(base64Encoded: audioData)
    }
    
    /// Convert to JSON string for P2P transmission
    func toJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
    
    /// Parse from JSON string received via P2P
    static func fromJSONString(_ json: String) -> VoiceData? {
        guard let data = json.data(using: .utf8),
              let voice = try? JSONDecoder().decode(VoiceData.self, from: data) else {
            return nil
        }
        return voice
    }
}
