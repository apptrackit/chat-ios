import SwiftUI
import UIKit
import Combine

// Reusable top toolbar showing Settings and signaling status (dot + text in the center)
struct SignalingToolbar: ViewModifier {
    @EnvironmentObject private var chat: ChatManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var isExpanded = false
    @State private var showJoinPopup = false
    @State private var showCreatePopup = false
    // Deep link naming state
    @State private var showDeepLinkNameStep = false
    @State private var newRoomTempName: String = ""
    @FocusState private var nameFieldFocused: Bool

    func body(content: Content) -> some View {
        ZStack {
            content
            
            // Deep Link Join Modal
            if let code = chat.pendingDeepLinkCode {
                DeepLinkJoinModal(
                    code: code,
                    showDeepLinkNameStep: $showDeepLinkNameStep,
                    newRoomTempName: $newRoomTempName,
                    nameFieldFocused: $nameFieldFocused,
                    onConfirmJoin: confirmDeepLinkJoinWithNaming,
                    onFinalizeJoinName: finalizeDeepLinkJoinName,
                    onCancel: { chat.cancelPendingDeepLinkJoin() }
                )
            }
            
            // Join Room Modal
            if showJoinPopup {
                JoinRoomModal(isPresented: $showJoinPopup)
            }
            
            // Create Room Modal
            if showCreatePopup {
                CreateRoomModal(isPresented: $showCreatePopup)
            }
        }
        .onDisappear { isExpanded = false }
        .onChange(of: scenePhase) { _ in isExpanded = false }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    withAnimation(.spring()) {
                        guard chat.connectionStatus == .connected else { return }
                        if isExpanded { 
                            showJoinPopup = true
                            isExpanded = false 
                        } else { 
                            isExpanded = true 
                        }
                    }
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .accessibilityLabel("Join")
                .disabled(chat.connectionStatus != .connected)

                if isExpanded {
                    Button {
                        withAnimation(.spring()) {
                            guard chat.connectionStatus == .connected else { return }
                            showCreatePopup = true
                            isExpanded = false
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create")
                    .disabled(chat.connectionStatus != .connected)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .allowsHitTesting(false)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .allowsHitTesting(false)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Signaling status: \(statusText)")
            }
        }
    }

    // MARK: - Status Properties
    private var statusColor: Color {
        switch chat.connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    private var statusText: String {
        switch chat.connectionStatus {
        case .connected: return "Connected"
        case .connecting, .disconnected: return "Waiting"
        }
    }
    
    // MARK: - Deep Link Handlers
    private func confirmDeepLinkJoinWithNaming() {
        guard let code = chat.pendingDeepLinkCode else { return }
        guard chat.connectionStatus == .connected else { return }
        
        Task { @MainActor in
            // Use custom deep link join that will trigger naming step
            if await chat.confirmPendingDeepLinkJoinWithNaming(code: code) {
                withAnimation(.spring()) {
                    showDeepLinkNameStep = true
                }
                // Focus name field after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    nameFieldFocused = true
                }
            } else {
                // Join failed, could show error feedback
                withAnimation(.shake()) { }
            }
        }
    }
    
    private func finalizeDeepLinkJoinName(_ name: String?) {
        // Find most recent accepted session without name (created by others)
        if let session = chat.sessions.first(where: { $0.status == .accepted && $0.isCreatedByMe == false && ($0.name == nil || $0.name?.isEmpty == true) }) {
            chat.renameSession(session, newName: name?.isEmpty == true ? nil : name)
        }
        withAnimation(.spring()) {
            showDeepLinkNameStep = false
            newRoomTempName = ""
        }
        chat.cancelPendingDeepLinkJoin()
    }
}

// MARK: - Shake animation util
private extension Animation {
    static func shake() -> Animation { .easeInOut(duration: 0.12) }
}

extension View {
    func signalingToolbar() -> some View { self.modifier(SignalingToolbar()) }
}
