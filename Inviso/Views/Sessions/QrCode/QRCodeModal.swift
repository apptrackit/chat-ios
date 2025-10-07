//
//  QRCodeModal.swift
//  Inviso
//
//  Reusable QR code modal overlay for sharing join codes
//

import SwiftUI

struct QRCodeModal: View {
    let session: ChatSession
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture {
                    withAnimation(.spring()) { isPresented = false }
                }
            
            VStack(spacing: 16) {
                Text(session.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                QRCodeView(value: "inviso://join/" + session.code, size: 260)
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
                    .padding(.bottom, 4)
                
                Text("inviso://join/" + session.code)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal)
                
                Button("Close") {
                    withAnimation(.spring()) { isPresented = false }
                }
                .padding(.top, 4)
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

#Preview {
    @Previewable @State var isPresented = true
    
    ZStack {
        Color.gray.ignoresSafeArea()
        if isPresented {
            QRCodeModal(
                session: ChatSession(name: "Test Room", code: "123456"),
                isPresented: $isPresented
            )
        }
    }
}
