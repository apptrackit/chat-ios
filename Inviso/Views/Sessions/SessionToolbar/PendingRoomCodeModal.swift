//
//  PendingRoomCodeModal.swift
//  Inviso
//
//  Displays code and QR for an existing pending session
//

import SwiftUI

struct PendingRoomCodeModal: View {
    @EnvironmentObject private var chat: ChatManager
    let session: ChatSession
    @Binding var isPresented: Bool
    @State private var showQRCode = false
    @State private var showCopied = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture {
                    withAnimation(.spring()) { isPresented = false }
                }

            VStack(spacing: 14) {
                if !showQRCode {
                    // Code display screen
                    Text("Room Code")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let name = session.name, !name.isEmpty {
                        Text(name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Countdown if exists
                    if let expires = session.expiresAt {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.caption)
                            CountdownTimerView(expiresAt: expires)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    // Code digits
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { idx in
                            if idx < session.code.count {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.15))
                                    Text(String(session.code[session.code.index(session.code.startIndex, offsetBy: idx)]))
                                        .font(.system(size: 26, weight: .bold, design: .rounded))
                                }
                                .frame(width: 48, height: 56)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    
                    // Copy button
                    Button {
                        UIPasteboard.general.string = session.code
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
                    
                    // QR button
                    Button {
                        withAnimation(.spring()) { showQRCode = true }
                    } label: {
                        Label("Show QR", systemImage: "qrcode")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 2)

                    // Close button
                    Button("Close") {
                        withAnimation(.spring()) {
                            isPresented = false
                        }
                    }
                    .padding(.top, 4)
                } else {
                    // QR Code View
                    Text("Share Join Code")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if session.code.count == 6 {
                        QRCodeView(value: "inviso://join/\(session.code)", size: 260)
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
                        
                        Text(session.code)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .foregroundColor(.primary)
                            .padding(.top, 8)
                        
                        Text("inviso://join/\(session.code)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        ProgressView()
                            .padding()
                    }
                    
                    Button("Back") {
                        withAnimation(.spring()) { showQRCode = false }
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
        }
    }
}
