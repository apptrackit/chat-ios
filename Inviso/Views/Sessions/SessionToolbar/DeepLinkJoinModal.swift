//
//  DeepLinkJoinModal.swift
//  Inviso
//
//  Handles deep link join confirmations and room naming
//

import SwiftUI

struct DeepLinkJoinModal: View {
    let code: String
    @Binding var showDeepLinkNameStep: Bool
    @Binding var newRoomTempName: String
    var nameFieldFocused: FocusState<Bool>.Binding
    let onConfirmJoin: () -> Void
    let onFinalizeJoinName: (String?) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .transition(.opacity)
            
            VStack(spacing: 16) {
                if !showDeepLinkNameStep {
                    Text("Join via Link")
                        .font(.headline)
                    Text("Code: \(code)")
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    Text("You opened a link containing a join code. Confirm to proceed.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    HStack(spacing: 24) {
                        Button("Cancel") {
                            withAnimation(.spring()) { onCancel() }
                        }
                        Button {
                            onConfirmJoin()
                        } label: {
                            Label("Join", systemImage: "arrow.right.circle.fill")
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                    }
                } else {
                    Text("Name This Room")
                        .font(.headline)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Room name", text: $newRoomTempName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused(nameFieldFocused)
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
                            onFinalizeJoinName(nil)
                        }
                        Button("Save") {
                            onFinalizeJoinName(newRoomTempName.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        .buttonStyle(.glass)
                        .disabled(newRoomTempName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.15))
            )
            .padding()
            .transition(.scale.combined(with: .opacity))
        }
    }
}