//
//  VoiceMessageBubble.swift
//  Inviso
//
//  Refined voice message bubble with adaptive waveform and glass styling.
//

import SwiftUI
import UIKit

struct VoiceMessageBubble: View {
    let voice: VoiceData
    let isFromSelf: Bool
    let showTime: Bool
    let timestamp: Date
    
    @StateObject private var player = VoicePlayer()
    @State private var isLoading = true
    @State private var loadError = false
    
    private var accentColor: Color {
        isFromSelf ? Color(red: 0.04, green: 0.48, blue: 1.0) : Color(red: 0.32, green: 0.78, blue: 0.58)
    }
    
    private var bubbleGradient: LinearGradient {
        LinearGradient(
            colors: isFromSelf
                ? [Color(red: 0.04, green: 0.32, blue: 0.9).opacity(0.82), Color(red: 0.05, green: 0.22, blue: 0.6).opacity(0.75)]
                : [Color(red: 0.24, green: 0.34, blue: 0.45).opacity(0.78), Color(red: 0.12, green: 0.18, blue: 0.26).opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var bubbleMaxWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.72, 340)
    }
    
    private var durationLabel: String {
        formatDuration(player.isPlaying ? player.currentTime : voice.duration)
    }
    
    var body: some View {
        VStack(alignment: isFromSelf ? .trailing : .leading, spacing: 6) {
            if showTime {
                Text(timestamp.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            
            HStack(alignment: .center, spacing: 16) {
                playbackButton
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Voice note", systemImage: "waveform")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08), in: Capsule())
                        Spacer()
                        Text(durationLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    
                    if loadError {
                        Text("Voice note unavailable")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.red.opacity(0.85))
                    } else {
                        WaveformProgressView(
                            samples: voice.waveform,
                            progress: player.playbackProgress,
                            color: accentColor
                        )
                        .frame(height: 36)
                    }
                    
                    HStack(alignment: .center) {
                        Label(player.isPlaying ? "Playing" : "Tap to listen", systemImage: player.isPlaying ? "speaker.wave.2" : "play.circle")
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.75))
                        Spacer()
                        Label("E2EE", systemImage: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
            }
            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
            .padding(.vertical, 18)
            .padding(.horizontal, 18)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(bubbleGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: accentColor.opacity(0.28), radius: 16, x: 0, y: 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: isFromSelf ? .trailing : .leading)
        .padding(.horizontal, 12)
        .onAppear {
            loadAudio()
        }
        .onDisappear {
            player.stop()
        }
    }
    
    private var playbackButton: some View {
        Button {
            togglePlayback()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accentColor.opacity(0.7), accentColor.opacity(0.25)],
                            center: .center,
                            startRadius: 4,
                            endRadius: 48
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: accentColor.opacity(0.35), radius: 12, y: 4)
                
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.02, player.playbackProgress)))
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 52, height: 52)
                    .opacity(loadError || isLoading ? 0 : 1)
                    .animation(.easeOut(duration: 0.18), value: player.playbackProgress)
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if loadError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Color.red.opacity(0.9))
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.black))
                        .foregroundStyle(Color.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading || loadError)
    }
    
    private func loadAudio() {
        guard let audioData = voice.decodedAudioData else {
            loadError = true
            isLoading = false
            return
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_\(UUID().uuidString).m4a")
        
        do {
            try audioData.write(to: tempURL)
            try player.load(url: tempURL)
            isLoading = false
        } catch {
            loadError = true
            isLoading = false
            print("Failed to load voice message: \(error)")
        }
    }
    
    private func togglePlayback() {
        guard !loadError else { return }
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Adaptive Waveform Rendering
struct WaveformProgressView: View {
    let samples: [Float]
    let progress: Double
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width, 1)
            // Reduce bar count to prevent overflow - more spacing between fewer bars
            let maxBars = Int(availableWidth / 4.5) // Increased spacing from 3 to 4.5
            let barCount = max(20, min(samples.count, maxBars))
            let spacing: CGFloat = 2.5 // Increased from 2
            let totalSpacing = spacing * CGFloat(max(0, barCount - 1))
            let barWidth = max(2.0, min(3.0, (availableWidth - totalSpacing) / CGFloat(max(barCount, 1))))
            let values = interpolatedSamples(count: barCount)
            
            HStack(spacing: spacing) {
                ForEach(0..<values.count, id: \.self) { index in
                    let itemProgress = Double(index) / Double(max(values.count - 1, 1))
                    Capsule()
                        .fill(itemProgress <= progress ? color : color.opacity(0.24))
                        .overlay(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [color.opacity(itemProgress <= progress ? 0.9 : 0.35), color.opacity(0.2)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .frame(width: barWidth)
                        .frame(height: max(4, CGFloat(values[index]) * geometry.size.height * 0.9)) // Reduced max height
                }
            }
            .frame(width: availableWidth, height: geometry.size.height, alignment: .center)
        }
    }
    
    private func interpolatedSamples(count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else {
            return (0..<count).map { _ in Float.random(in: 0.25...0.9) }
        }
        let step = Double(samples.count) / Double(count)
        var result: [Float] = []
        for index in 0..<count {
            let sampleIndex = Int(Double(index) * step)
            result.append(max(0.06, samples[min(sampleIndex, samples.count - 1)]))
        }
        return result
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.8).ignoresSafeArea()
        VStack(spacing: 24) {
            VoiceMessageBubble(
                voice: VoiceData(
                    duration: 5.2,
                    waveform: (0..<160).map { _ in Float.random(in: 0.2...1.0) },
                    audioData: Data()
                ),
                isFromSelf: false,
                showTime: true,
                timestamp: Date()
            )
            
            VoiceMessageBubble(
                voice: VoiceData(
                    duration: 42.8,
                    waveform: (0..<200).map { _ in Float.random(in: 0.2...1.0) },
                    audioData: Data()
                ),
                isFromSelf: true,
                showTime: false,
                timestamp: Date()
            )
        }
        .padding()
    }
}
