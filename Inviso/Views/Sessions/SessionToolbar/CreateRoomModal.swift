//
//  CreateRoomModal.swift
//  Inviso
//
//  Handles creating new rooms with names, durations, and QR code sharing
//

import SwiftUI

struct CreateRoomModal: View {
    @EnvironmentObject private var chat: ChatManager
    @Binding var isPresented: Bool
    @State private var roomName: String = ""
    @State private var durationMinutes: Int = 5
    @FocusState private var createNameFocused: Bool
    @State private var showCreateResult = false
    @State private var createdCode: String = ""
    @State private var showCreatedQRCode = false
    @State private var showCopied = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture {
                    createNameFocused = false
                    endEditing()
                    withAnimation(.spring()) { isPresented = false }
                }

            VStack(spacing: 14) {
                if !showCreatedQRCode {
                    if showCreateResult == false {
                        Text("Create Room")
                            .font(.headline)
                            .foregroundColor(.primary)

                    // Room name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Optional room name", text: $roomName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($createNameFocused)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15))
                            )
                    }

                    // Duration (fixed options)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Expires in")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            ForEach([1, 5, 60, 720, 1440], id: \.self) { preset in
                                Button(action: { durationMinutes = preset }) {
                                    Text(preset < 60 ? "\(preset)m" : (preset % 60 == 0 ? "\(preset/60)h" : "\(preset)m"))
                                        .font(.caption.weight(.semibold))
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(
                                            Capsule().fill(preset == durationMinutes ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text(formatDuration(durationMinutes))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 20) {
                        Button("Cancel", role: .cancel) {
                            createNameFocused = false
                            endEditing()
                            withAnimation(.spring()) { isPresented = false }
                        }
                        Button {
                            // Generate code, create pending on server via ChatManager
                            createNameFocused = false
                            endEditing()
                            createdCode = String((0..<6).map { _ in String(Int.random(in: 0...9)) }.joined())
                            _ = chat.createSession(name: roomName.isEmpty ? nil : roomName, minutes: durationMinutes, code: createdCode)
                            withAnimation(.spring()) { showCreateResult = true }
                        } label: {
                            Text("Create")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.glass)
                    }
                    } else {
                        // Result: show code + copy
                        Text("Room Created")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if roomName.isEmpty == false {
                            Text("\(roomName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 8) {
                            ForEach(0..<6, id: \.self) { idx in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.15))
                                    Text(String(createdCode[createdCode.index(createdCode.startIndex, offsetBy: idx)]))
                                        .font(.system(size: 26, weight: .bold, design: .rounded))
                                }
                                .frame(width: 48, height: 56)
                            }
                        }
                        
                        Button {
                            UIPasteboard.general.string = createdCode
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                showCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    showCopied = false
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(.body.weight(.semibold))
                                    .contentTransition(.symbolEffect(.replace))
                                Text(showCopied ? "Copied!" : "Copy code")
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .buttonStyle(.glass)
                        .padding(.top, 6)
                        
                        Button {
                            withAnimation(.spring()) { showCreatedQRCode = true }
                        } label: {
                            Label("Show QR", systemImage: "qrcode")
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                        .padding(.top, 2)

                        Button("Done") {
                            withAnimation(.spring()) {
                                isPresented = false
                                showCreateResult = false
                                roomName = ""
                                durationMinutes = 5
                                createdCode = ""
                            }
                        }
                        .padding(.top, 4)
                    }
                } else {
                    // QR Code View
                    Text("Share Join Code")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if createdCode.count == 6 {
                        QRCodeView(value: "inviso://join/\(createdCode)", size: 260)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                        
                        Text(createdCode)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .foregroundColor(.primary)
                            .padding(.top, 8)
                        
                        Text("inviso://join/\(createdCode)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        ProgressView()
                            .padding()
                    }
                    
                    Button("Back") {
                        withAnimation(.spring()) { showCreatedQRCode = false }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(18)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15))
            )
            .padding()
            .transition(.scale.combined(with: .opacity))
            .onAppear { createNameFocused = true }
        }
        .onChange(of: chat.sessions) {
            // Auto-close create popups when session becomes accepted (other client joined)
            if isPresented || showCreateResult || showCreatedQRCode {
                if let activeSession = chat.sessions.first(where: { $0.id == chat.activeSessionId }),
                   activeSession.status == .accepted {
                    withAnimation(.spring()) {
                        isPresented = false
                        showCreateResult = false
                        showCreatedQRCode = false
                        roomName = ""
                        durationMinutes = 5
                        createdCode = ""
                    }
                }
            }
        }
    }

    // MARK: - Helper Methods
    
    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func formatDuration(_ minutes: Int) -> String {
        switch minutes {
        case 1: return "1 minute"
        case 5: return "5 minutes"
        case 60: return "1 hour"
        case 720: return "12 hours"
        case 1440: return "24 hours"
        default:
            if minutes < 60 { return "\(minutes) minutes" }
            let h = minutes / 60
            return "\(h) hours"
        }
    }
}