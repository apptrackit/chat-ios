//
//  JoinRoomModal.swift
//  Inviso
//
//  Handles joining rooms via 6-digit codes, QR scanning, and naming
//

import SwiftUI
import Combine

struct JoinRoomModal: View {
    @EnvironmentObject private var chat: ChatManager
    @Binding var isPresented: Bool
    @State private var joinCode: String = ""
    @FocusState private var joinFieldFocused: Bool
    @State private var caretBlinkOn: Bool = true
    @State private var showNameStep = false
    @State private var newRoomTempName: String = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var showJoinScanner = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture {
                    if showNameStep {
                        // Ignore outside tap during name step to reduce accidental dismiss
                    } else {
                        joinFieldFocused = false
                        endEditing()
                        withAnimation(.spring()) { isPresented = false }
                    }
                }

            VStack(spacing: 14) {
                if !showNameStep {
                    Text("Enter Join Code")
                        .font(.headline)
                        .foregroundColor(.primary)

                    TextField("", text: $joinCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($joinFieldFocused)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .onChange(of: joinCode) { newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered.count > 6 {
                                joinCode = String(filtered.prefix(6))
                            } else if filtered != newValue {
                                joinCode = filtered
                            }
                        }

                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { idx in
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15))

                                let ch = character(at: idx)
                                Text(ch)
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .opacity(ch.isEmpty ? 0 : 1)
                                    .scaleEffect(ch.isEmpty ? 0.95 : 1.0)
                                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: ch)

                                if joinFieldFocused && joinCode.count < 6 && idx == joinCode.count && ch.isEmpty {
                                    Rectangle()
                                        .fill(Color.accentColor.opacity(0.9))
                                        .frame(width: 2, height: 24)
                                        .opacity(caretBlinkOn ? 1 : 0)
                                        .transition(.opacity)
                                }
                            }
                            .frame(width: 42, height: 50)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { joinFieldFocused = true }

                    HStack(spacing: 20) {
                        Button(role: .cancel) {
                            joinFieldFocused = false
                            endEditing()
                            withAnimation(.spring()) { isPresented = false }
                        } label: { Text("Cancel") }

                        Button {
                            let code = joinCode
                            Task { @MainActor in
                                if let roomId = await chat.acceptJoinCode(code) {
                                    // Create session and transition to naming step
                                    _ = chat.addAcceptedSession(name: nil, code: code, roomId: roomId, isCreatedByMe: false)
                                    chat.joinRoom(roomId: roomId)
                                    withAnimation(.spring()) {
                                        showNameStep = true
                                        joinFieldFocused = false
                                        endEditing()
                                    }
                                    // Focus name field after animation
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        nameFieldFocused = true
                                    }
                                } else {
                                    // Could show error feedback here
                                    withAnimation(.shake()) { }
                                }
                            }
                        } label: {
                            Text("Join")
                                .fontWeight(.semibold)
                        }
                        .disabled(joinCode.count != 6)
                        .buttonStyle(.glass)
                        .tint(joinCode.count == 6 ? .green : .gray)
                        
                        Button {
                            showJoinScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                        }
                        .accessibilityLabel("Scan QR code")
                    }
                } else {
                    Text("Name This Room")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Room name", text: $newRoomTempName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($nameFieldFocused)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.15))
                            )
                    }
                    .transition(.opacity.combined(with: .scale))
                    
                    HStack(spacing: 20) {
                        Button("Skip") {
                            finalizeJoinName(nil)
                        }
                        Button("Save") {
                            finalizeJoinName(newRoomTempName.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        .buttonStyle(.glass)
                        .disabled(newRoomTempName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15))
            )
            .padding()
            .transition(.scale.combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Enter 6 digit join code")
            .onAppear { joinFieldFocused = true }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: joinCode)
            .animation(.easeInOut(duration: 0.18), value: joinFieldFocused)
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                if isPresented && joinFieldFocused && joinCode.count < 6 {
                    withAnimation(.easeInOut(duration: 0.2)) { caretBlinkOn.toggle() }
                } else {
                    caretBlinkOn = true
                }
            }
        }
        .sheet(isPresented: $showJoinScanner) {
            QRCodeScannerContainer { code in
                if code.lowercased().hasPrefix("inviso://join/") {
                    if let c = code.split(separator: "/").last, c.count == 6 { 
                        joinCode = String(c)
                        showJoinScanner = false 
                    }
                }
            }
        }
    }

    // MARK: - Helper Methods
    
    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func character(at index: Int) -> String {
        guard index < joinCode.count else { return "" }
        let idx = joinCode.index(joinCode.startIndex, offsetBy: index)
        return String(joinCode[idx])
    }

    private func finalizeJoinName(_ name: String?) {
        // Find most recent accepted session without name (created by others)
        if let session = chat.sessions.first(where: { $0.status == .accepted && $0.isCreatedByMe == false && ($0.name == nil || $0.name?.isEmpty == true) }) {
            chat.renameSession(session, newName: name?.isEmpty == true ? nil : name)
        }
        withAnimation(.spring()) {
            showNameStep = false
            isPresented = false
            joinCode = ""
            newRoomTempName = ""
        }
    }
}

// MARK: - Shake animation util
private extension Animation {
    static func shake() -> Animation { .easeInOut(duration: 0.12) }
}