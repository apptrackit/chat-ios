//
//  VoiceRecordingView.swift
//  Inviso
//
//  Reimagined voice recorder overlay with floating glass design.
//

import SwiftUI
import UIKit

struct VoiceRecordingView: View {
    @StateObject private var recorder = VoiceRecorder()
    @StateObject private var player = VoicePlayer()
    
    @State private var recordingState: RecordingState = .recording
    @State private var recordedURL: URL?
    @State private var waveformSamples: [Float] = []
    @State private var samplingTimer: Timer?
    @State private var showError = false
    @State private var errorMessage = ""
    
    let onVoiceSent: (VoiceData) -> Void
    let onClose: () -> Void
    
    enum RecordingState {
        case recording
        case preview
        case playing
    }
    
    private var accentColor: Color {
        Color(red: 0.02, green: 0.46, blue: 1.0)
    }
    
    private var displayDuration: TimeInterval {
        switch recordingState {
        case .recording:
            return recorder.recordingDuration
        case .playing:
            return max(player.currentTime, 0)
        case .preview:
            return player.duration > 0 ? player.duration : recorder.recordingDuration
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture {
                    if recordingState != .recording {
                        closeAfterCleanup()
                    }
                }
            
            modalCard
                .transition(.scale(scale: 0.88).combined(with: .opacity))
                .shadow(color: .black.opacity(0.35), radius: 36, y: 22)
        }
        .onAppear {
            startRecording()
        }
        .onDisappear {
            samplingTimer?.invalidate()
            samplingTimer = nil
        }
        .alert("Recording Error", isPresented: $showError) {
            Button("OK", role: .cancel) {
                closeAfterCleanup(keepFile: false)
            }
            
            if recorder.error == .permissionDenied {
                Button("Open Settings") {
                    openSettings()
                    closeAfterCleanup(keepFile: false)
                }
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var modalCard: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(.white.opacity(0.38))
                .frame(width: 38, height: 4)
                .padding(.top, 6)
            
            VStack(spacing: 3) {
                Text(recordingState == .recording ? "Capturing voice note" : "Voice note ready")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Text(recordingState == .recording ? "End-to-end encrypted." : "Preview or send.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.top, 2)
            
            infoRow
            
            Text(formatDuration(displayDuration))
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .padding(.top, 1)
            
            recorderVisualization
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .padding(.top, 2)
            
            actionSection
                .padding(.horizontal, 2)
                .padding(.top, 6)
                .padding(.bottom, 3)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(GlassCardBackground(accent: accentColor))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                .blendMode(.plusLighter)
        )
        .frame(maxWidth: 310)
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private var recorderVisualization: some View {
        if recordingState == .recording {
            BreathingOrbView(level: recorder.recordingLevel, accent: accentColor)
        } else {
            VStack(spacing: 8) {
                WaveformReviewView(
                    samples: waveformSamples,
                    progress: player.playbackProgress,
                    accent: accentColor
                )
                .frame(height: 56)
                .padding(.horizontal, 4)
                
                HStack {
                    Label(recordingState == .playing ? "Playing" : "Preview", systemImage: recordingState == .playing ? "speaker.wave.2.fill" : "waveform.path.ecg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if recordingState != .recording {
                        Button {
                            if player.isPlaying {
                                player.pause()
                                recordingState = .preview
                            } else {
                                player.play()
                                recordingState = .playing
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                Text(player.isPlaying ? "Pause" : "Play")
                            }
                            .font(.caption2.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(accentColor)
                    }
                }
                .padding(.horizontal, 3)
            }
        }
    }
    
    private var infoRow: some View {
        HStack(spacing: 8) {
            InfoChip(icon: "lock.fill", text: "E2EE", color: accentColor)
            InfoChip(icon: "antenna.radiowaves.left.and.right", text: "P2P", color: .white.opacity(0.8))
            InfoChip(icon: recordingState == .recording ? "waveform.path" : "checkmark", text: recordingState == .recording ? "Live" : "Ready", color: .white.opacity(0.7))
            Spacer()
        }
    }
    
    @ViewBuilder
    private var actionSection: some View {
        if recordingState == .recording {
            HStack(spacing: 12) {
                actionButton(title: nil, icon: "xmark", style: .ghost) {
                    cancelRecording()
                }
                actionButton(title: nil, icon: "stop.fill", style: .ghost) {
                    stopRecording()
                }
                actionButton(title: nil, icon: "paperplane.fill", style: .accent) {
                    stopAndSend()
                }
            }
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    actionButton(title: nil, icon: "trash", style: .destructive) {
                        cancelRecording()
                    }
                    actionButton(title: nil, icon: "arrow.counterclockwise", style: .ghost) {
                        restartRecording()
                    }
                }
                actionButton(title: nil, icon: "paperplane.fill", style: .accent) {
                    sendVoiceMessage()
                }
            }
        }
    }
    
    private func startRecording() {
        Task {
            do {
                recordedURL = try await recorder.startRecording()
                recordingState = .recording
                waveformSamples.removeAll()
                startSampling()
            } catch let error as VoiceRecorder.RecordingError {
                errorMessage = error.localizedDescription
                showError = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func startSampling() {
        samplingTimer?.invalidate()
        samplingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak recorder] _ in
            Task { @MainActor [weak recorder] in
                guard let recorder = recorder, recorder.isRecording else {
                    return
                }
                waveformSamples.append(max(0.05, recorder.recordingLevel))
                if waveformSamples.count > 480 {
                    waveformSamples.removeFirst(waveformSamples.count - 480)
                }
            }
        }
    }
    
    private func stopSampling() {
        samplingTimer?.invalidate()
        samplingTimer = nil
    }
    
    private func stopRecording() {
        guard recordingState == .recording else { return }
        stopSampling()
        if let url = recorder.stopRecording() {
            recordedURL = url
            do {
                try player.load(url: url)
            } catch {
                errorMessage = "Failed to prepare playback."
                showError = true
            }
            recordingState = .preview
        }
    }
    
    private func stopAndSend() {
        if recordingState == .recording {
            // Stop recording and send immediately without showing preview
            stopSampling()
            
            guard let url = recorder.stopRecording() else { return }
            recordedURL = url
            
            // Send immediately
            guard let audioData = try? Data(contentsOf: url) else {
                errorMessage = "Failed to read audio file"
                showError = true
                return
            }
            
            let downsampledWaveform = downsample(waveformSamples, to: 120)
            let duration = recorder.recordingDuration
            let voiceData = VoiceData(
                duration: duration,
                waveform: downsampledWaveform,
                audioData: audioData
            )
            
            onVoiceSent(voiceData)
            closeAfterCleanup(keepFile: false)
        } else {
            sendVoiceMessage()
        }
    }
    
    private func restartRecording() {
        stopSampling()
        player.stop()
        if let url = recordedURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedURL = nil
        waveformSamples.removeAll()
        recorder.reset()
        recordingState = .recording
        startRecording()
    }
    
    private func cancelRecording() {
        stopSampling()
        recorder.cancelRecording()
        recordedURL = nil
        closeAfterCleanup(keepFile: false)
    }
    
    private func sendVoiceMessage() {
        guard let url = recordedURL else { return }
        guard let audioData = try? Data(contentsOf: url) else {
            errorMessage = "Failed to read audio file"
            showError = true
            return
        }
        
        let downsampledWaveform = downsample(waveformSamples, to: 120)
        let duration = player.duration > 0 ? player.duration : recorder.recordingDuration
        let voiceData = VoiceData(
            duration: duration,
            waveform: downsampledWaveform,
            audioData: audioData
        )
        
        onVoiceSent(voiceData)
        closeAfterCleanup(keepFile: false)
    }
    
    private func downsample(_ samples: [Float], to targetCount: Int) -> [Float] {
        guard !samples.isEmpty else { return (0..<targetCount).map { _ in Float.random(in: 0.25...0.85) } }
        guard samples.count > targetCount else { return samples }
        let step = Double(samples.count) / Double(targetCount)
        var result: [Float] = []
        for i in 0..<targetCount {
            let index = Int(Double(i) * step)
            result.append(samples[min(index, samples.count - 1)])
        }
        return result
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func closeAfterCleanup(keepFile: Bool = false) {
        stopSampling()
        player.stop()
        if !keepFile, let url = recordedURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedURL = nil
        waveformSamples.removeAll()
        recorder.reset()
        recordingState = .recording
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            onClose()
        }
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            Task {
                await UIApplication.shared.open(url)
            }
        }
    }
    
    private enum ActionStyle {
        case ghost
        case accent
        case destructive
    }
    
    private func actionButton(title: String?, icon: String, style: ActionStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                if let title = title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(background(for: style))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(strokeColor(for: style), lineWidth: 1)
            )
            .foregroundStyle(foreground(for: style))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: style == .accent ? accentColor.opacity(0.25) : .clear, radius: style == .accent ? 10 : 0, y: style == .accent ? 5 : 0)
        }
        .buttonStyle(.plain)
    }
    
    private func background(for style: ActionStyle) -> some ShapeStyle {
        switch style {
        case .ghost:
            return AnyShapeStyle(.ultraThinMaterial)
        case .accent:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [accentColor.opacity(0.95), accentColor.opacity(0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .destructive:
            return AnyShapeStyle(Color.red.opacity(0.18))
        }
    }
    
    private func foreground(for style: ActionStyle) -> Color {
        switch style {
        case .ghost:
            return .primary
        case .accent:
            return .white
        case .destructive:
            return Color.red.opacity(0.9)
        }
    }
    
    private func strokeColor(for style: ActionStyle) -> Color {
        switch style {
        case .ghost:
            return .white.opacity(0.12)
        case .accent:
            return .white.opacity(0.18)
        case .destructive:
            return Color.red.opacity(0.35)
        }
    }
}

// MARK: - Supporting Views

private struct GlassCardBackground: View {
    let accent: Color
    
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.28), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 18)
                    .opacity(0.9)
            }
    }
}

private struct BreathingOrbView: View {
    let level: Float
    let accent: Color
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.5), accent.opacity(0.05)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .scaleEffect(1 + CGFloat(level) * 0.4)
                .blur(radius: 20)
            
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 120, height: 120)
                .overlay {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [accent.opacity(0.9), accent.opacity(0.1), accent.opacity(0.9)],
                                center: .center
                            ),
                            lineWidth: 2.5
                        )
                        .opacity(0.6)
                }
                .overlay {
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.08, level)))
                        .stroke(accent.opacity(0.85), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.12), value: level)
                }
                .shadow(color: accent.opacity(0.35), radius: 20, y: 6)
            
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(accent.opacity(0.25))
                    .frame(width: 6, height: 6)
                    .offset(x: 50)
                    .rotationEffect(.degrees(Double(index) / 8 * 360))
                    .blur(radius: 0.5)
            }
            
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(accent.opacity(0.85))
                .shadow(color: accent.opacity(0.45), radius: 14, y: 5)
        }
        .frame(width: 140, height: 140)
    }
}

private struct WaveformReviewView: View {
    let samples: [Float]
    let progress: Double
    let accent: Color
    
    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let barCount = max(28, min(samples.count, Int(width / 3)))
            let spacing: CGFloat = 2
            let totalSpacing = spacing * CGFloat(max(barCount - 1, 0))
            let barWidth = max(2.5, (width - totalSpacing) / CGFloat(max(barCount, 1)))
            let values = interpolatedSamples(count: barCount)
            
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<values.count, id: \.self) { index in
                    let itemProgress = Double(index) / Double(max(values.count - 1, 1))
                    Capsule()
                        .fill(itemProgress <= progress ? accent : Color.white.opacity(0.18))
                        .overlay(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            accent.opacity(itemProgress <= progress ? 0.95 : 0.45),
                                            accent.opacity(itemProgress <= progress ? 0.4 : 0.15)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .frame(width: barWidth)
                        .frame(height: max(6, CGFloat(values[index]) * geometry.size.height))
                }
            }
            .frame(width: width, height: geometry.size.height)
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
            result.append(max(0.05, samples[min(sampleIndex, samples.count - 1)]))
        }
        return result
    }
}

private struct InfoChip: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule(style: .continuous))
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.3).ignoresSafeArea()
        VoiceRecordingView { voice in
            print("Voice sent: \(voice.duration)s")
        } onClose: {}
    }
}
