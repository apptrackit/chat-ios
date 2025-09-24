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
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class OnDeviceLLMManager: ObservableObject {
    // Public published state for UI
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isSupported: Bool = false
    @Published private(set) var isGenerating: Bool = false
    @Published var systemPrompt: String = "You are a helpful assistant. Keep replies concise."
    @Published private(set) var isCancelled: Bool = false
    @Published private(set) var lastError: String? = nil

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private var session: LanguageModelSession? = nil
    @available(iOS 26.0, *)
    private var currentTask: Task<Void, Never>? = nil
#endif

    init() {
        self.isSupported = Self.checkDeviceSupport()
        if !isSupported {
            appendSystem("On‑device LLM not available on this device / OS version.")
        } else {
            appendSystem("On‑device LLM ready. Ask me something.")
#if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                session = LanguageModelSession(instructions: systemPrompt)
            }
#endif
        }
    }

    static func checkDeviceSupport() -> Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // Basic availability: ensure default model reports .available
            let available: Bool
            if let defaultModel = try? _getDefaultModelAvailability() {
                available = defaultModel
            } else {
                available = true // optimistic if API succeeds but availability query fails
            }
            return available
        }
        return false
#else
        return false
#endif
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func _getDefaultModelAvailability() throws -> Bool {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available: return true
        default: return false
        }
    }
#endif

    func sendUser(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(text: trimmed, timestamp: Date(), isFromSelf: true))
        isCancelled = false
        lastError = nil
        Task { await generateResponse(for: trimmed) }
    }

    private func appendSystem(_ text: String) {
        messages.append(ChatMessage(text: text, timestamp: Date(), isFromSelf: false, isSystem: true))
    }

    private func generateResponse(for userText: String) async {
        guard isSupported else { return }
        isGenerating = true
        defer { isGenerating = false }

#if canImport(FoundationModels)
        if #available(iOS 26.0, *), let session {
            currentTask?.cancel()
            let myTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let response = try await session.respond(to: userText)
                    let mirror = Mirror(reflecting: response)
                    let replyText = (
                        mirror.children.first(where: { $0.label == "content" })?.value as? String ??
                        mirror.children.first(where: { $0.label == "rawContent" })?.value as? String ??
                        mirror.children.first(where: { $0.label == "text" })?.value as? String ??
                        String(describing: response)
                    )
                    await MainActor.run {
                        self.messages.append(ChatMessage(text: replyText, timestamp: Date(), isFromSelf: false))
                    }
                } catch is CancellationError {
                    await MainActor.run { self.isCancelled = true }
                } catch {
                    await MainActor.run { self.lastError = error.localizedDescription }
                }
            }
            currentTask = myTask
            await myTask.value
            return
        }
#endif
        // Fallback placeholder path (older OS or module not present)
        try? await Task.sleep(nanoseconds: 400_000_000)
        let reply = "(Fallback) You said: \(userText)"
        messages.append(ChatMessage(text: reply, timestamp: Date(), isFromSelf: false))
    }

    func cancelGeneration() {
        guard isGenerating else { return }
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            currentTask?.cancel()
        }
#endif
        isCancelled = true
    }
}
