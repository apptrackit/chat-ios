//
//  OnDeviceLLMManager.swift
//  Inviso
//
//  Created on 9/24/25.
//
//  Provides a thin wrapper around Apple's on‑device foundation model APIs (iOS 26+).
//  Uses soft reflection / availability so the project still compiles on earlier SDKs.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class OnDeviceLLMManager: ObservableObject {
    // Public published state for UI
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isSupported: Bool = false
    @Published private(set) var isGenerating: Bool = false
    @Published var systemPrompt: String = "You are a helpful on‑device assistant."

    // Simple placeholder: in real iOS 26 integration, initialize model (e.g., via FoundationModels API)
    init() {
        self.isSupported = Self.checkDeviceSupport()
        if !isSupported {
            appendSystem("On‑device LLM not available on this device / OS version.")
        } else {
            appendSystem("On‑device LLM ready. Ask me something.")
        }
    }

    static func checkDeviceSupport() -> Bool {
        // Strictly gate by runtime availability (iOS 26). Replace with actual API availability checks.
        if #available(iOS 26.0, *) { return true } else { return false }
    }

    func sendUser(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(text: trimmed, timestamp: Date(), isFromSelf: true))
        Task { await generateResponse(for: trimmed) }
    }

    private func appendSystem(_ text: String) {
        messages.append(ChatMessage(text: text, timestamp: Date(), isFromSelf: false, isSystem: true))
    }

    private func generateResponse(for userText: String) async {
        guard isSupported else { return }
        isGenerating = true
        defer { isGenerating = false }

        // Placeholder generation. Replace with streaming tokens from FoundationModels when available.
        // Simulate latency.
        try? await Task.sleep(nanoseconds: 600_000_000)
        let reply = "(Local LLM) You said: \(userText). This is a placeholder response until the real on‑device model integration is implemented."
        messages.append(ChatMessage(text: reply, timestamp: Date(), isFromSelf: false))
    }
}
