//
//  CreateRoomModal.swift
//  Inviso
//
//  Handles creating new contacts with names, durations, and QR code sharing
//

import SwiftUI

struct CreateRoomModal: View {
    @EnvironmentObject private var chat: ChatManager
    @Binding var isPresented: Bool
    @State private var contactName: String = ""
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

            VStack(spacing: 18) {
                if !showCreatedQRCode {
                    if showCreateResult == false {
                        VStack(spacing: 6) {
                            Text("New Contact")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.primary)
                            
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                        .padding(.bottom, 4)

                    // Contact name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contact Name")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                        TextField("Name of you contact", text: $contactName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($createNameFocused)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15))
                            )
                    }

                    // Message lifetime (fixed options)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Join code expires in")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                        HStack(spacing: 8) {
                            ForEach([1, 5, 60, 720, 1440], id: \.self) { preset in
                                Button(action: { durationMinutes = preset }) {
                                    Text(preset < 60 ? "\(preset)m" : (preset % 60 == 0 ? "\(preset/60)h" : "\(preset)m"))
                                        .font(.caption.weight(.semibold))
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 14)
                                        .background(
                                            Capsule().fill(preset == durationMinutes ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(spacing: 12) {
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
                            _ = chat.createSession(name: contactName.isEmpty ? nil : contactName, minutes: durationMinutes, code: createdCode)
                            withAnimation(.spring()) { showCreateResult = true }
                        } label: {
                            Text("Create Contact")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.top, 4)
                    } else {
                        // Result: show code + copy
                        VStack(spacing: 16) {
                            VStack(spacing: 6) {
                                Text("Contact Ready!")
                                    .font(.title2.weight(.bold))
                                    .foregroundColor(.primary)
                                
                                Text("Share this code with them to connect")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
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
                            .padding(.vertical, 4)
                            
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
                                HStack(spacing: 8) {
                                    Image(systemName: showCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                        .font(.body.weight(.semibold))
                                        .contentTransition(.symbolEffect(.replace))
                                    Text(showCopied ? "Copied!" : "Copy Code")
                                        .font(.body.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            
                            Button {
                                withAnimation(.spring()) { showCreatedQRCode = true }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "qrcode")
                                        .font(.body.weight(.semibold))
                                    Text("Show QR Code")
                                        .font(.body.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)

                            Button("Done") {
                                withAnimation(.spring()) {
                                    isPresented = false
                                    showCreateResult = false
                                    contactName = ""
                                    durationMinutes = 5
                                    createdCode = ""
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                } else {
                    // QR Code View
                    VStack(spacing: 16) {
                        VStack(spacing: 6) {
                            Text("Share Connection Code")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.primary)
                            
                            Text("Have them scan this QR code to connect")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
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
                                .font(.system(.title2, design: .monospaced).weight(.bold))
                                .foregroundColor(.primary)
                                .padding(.top, 4)
                            
                            if contactName.isEmpty == false {
                                Text(contactName)
                                    .font(.headline)
                                    .foregroundColor(.accentColor)
                            }
                        } else {
                            ProgressView()
                                .padding()
                        }
                        
                        Button("Back") {
                            withAnimation(.spring()) { showCreatedQRCode = false }
                        }
                        .padding(.top, 8)
                    }
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
                        contactName = ""
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