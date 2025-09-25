//
//  LLMView.swift
//  Inviso
//
//  Created on 9/24/25.
//
//  Placeholder view for upcoming on-device LLM features.
//

import SwiftUI

struct LLMView: View {
    @StateObject private var llm = OnDeviceLLMManager()
    @State private var input: String = ""

    var body: some View {
        ZStack(alignment: .center) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(llm.messages.enumerated()), id: \.element.id) { index, msg in
                            if msg.isSystem {
                                Text(msg.text)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 2)
                                    .id(msg.id)
                                    .padding(.horizontal)
                            } else {
                                let showTime = index == 0 || !Calendar.current.isDate(msg.timestamp, equalTo: llm.messages[index - 1].timestamp, toGranularity: .minute)
                                ChatBubble(message: MessageItem(id: msg.id, text: msg.text, isFromSelf: msg.isFromSelf, time: msg.timestamp), showTime: showTime)
                                    .id(msg.id)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: llm.messages.count) { oldValue, newValue in
                    guard newValue > oldValue, let last = llm.messages.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .navigationTitle("LLM")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if let err = llm.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            } else if llm.isCancelled {
                Text("Generation cancelled")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
            let hasText = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            HStack(spacing: 8) {
                SearchBarField(text: $input, placeholder: llm.isSupported ? (llm.isGenerating ? "Generating…" : "Message") : "Unsupported", onSubmit: { send() })
                    .frame(height: 36)
                    .disabled(!llm.isSupported || llm.isGenerating)
                    .opacity(llm.isSupported ? 1 : 0.6)
                if llm.isGenerating {
                    Button(role: .destructive) { llm.cancelGeneration() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    .frame(width: 36, height: 36)
                    .transition(.opacity)
                } else if hasText && llm.isSupported {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(red: 0.0, green: 0.35, blue: 1.0))
                            .frame(width: 36, height: 36)
                    }
                    .transition(.scale.combined(with: .opacity))
                    .buttonStyle(.glass)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: input)
        }
        .modifier(GlassContainerModifier())
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, llm.isSupported, !llm.isGenerating else { return }
        llm.sendUser(trimmed)
        input = ""
    }
}

#Preview { NavigationStack { LLMView() } }
