import SwiftUI

/// A liquid glass connection indicator card showing P2P and encryption status
/// Uses iOS modern glass materials for a premium look
struct ConnectionIndicatorCard: View {
    @EnvironmentObject private var chat: ChatManager
    @State private var showDisconnectConfirm = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Show different status based on join state
            if !chat.isJoinedToRoom {
                viewingModeSection
            } else if chat.isP2PConnected {
                connectionStatusSection
            } else {
                waitingForConnectionSection
            }
            
            // Encryption status (only show if P2P is connected or encryption is in progress)
            if chat.isEncryptionReady || chat.keyExchangeInProgress {
                Divider()
                    .overlay(Color.white.opacity(0.1))
                
                encryptionStatusSection
            }
            
            // Disconnect button (only show when connected)
            if chat.isP2PConnected {
                Divider()
                    .overlay(Color.white.opacity(0.1))
                
                disconnectSection
            }
            
            // Cancel button when waiting
            if chat.isJoinedToRoom && !chat.isP2PConnected {
                Divider()
                    .overlay(Color.white.opacity(0.1))
                
                cancelConnectionSection
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.clear)
                .glassEffect(in: .rect(cornerRadius: 24))
        )
        .clipShape(
            .rect(cornerRadius: 24, style: .continuous)
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .alert("Disconnect?", isPresented: $showDisconnectConfirm) {
            Button("Disconnect", role: .destructive) {
                chat.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will close the P2P connection but keep you in the chat. You can reconnect anytime.")
        }
    }
    
    // MARK: - Connection Status Section
    
    private var connectionStatusSection: some View {
        HStack(spacing: 12) {
            // Icon with subtle animation
            Image(systemName: iconForPath(chat.connectionPath))
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            colorForPath(chat.connectionPath),
                            colorForPath(chat.connectionPath).opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
            
            // Text info
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.connectionPath.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(latencyHint)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 0)
            
            // Status badge
            Text(chat.connectionPath.shortLabel)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(colorForPath(chat.connectionPath))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(colorForPath(chat.connectionPath).opacity(0.15))
                        .overlay(
                            Capsule()
                                .strokeBorder(colorForPath(chat.connectionPath).opacity(0.3), lineWidth: 0.5)
                        )
                )
        }
    }
    
    // MARK: - Viewing Mode Section
    
    private var viewingModeSection: some View {
        HStack(spacing: 12) {
            // Eye icon for viewing mode
            Image(systemName: "eye.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
            
            // Text info
            VStack(alignment: .leading, spacing: 3) {
                Text("Viewing Mode")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Tap Join to connect")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 0)
            
            // Status badge
            Text("NOT JOINED")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.15))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.blue.opacity(0.3), lineWidth: 0.5)
                        )
                )
        }
    }
    
    // MARK: - Waiting Section
    
    private var waitingForConnectionSection: some View {
        HStack(spacing: 12) {
            // Animated progress indicator
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                .scaleEffect(0.9)
                .frame(width: 32, height: 32)
            
            // Text info
            VStack(alignment: .leading, spacing: 3) {
                Text("Waiting for Peer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Establishing P2P connection…")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 0)
            
            // Status badge
            Text("WAITING")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.yellow)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.yellow.opacity(0.15))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 0.5)
                        )
                )
        }
    }
    
    // MARK: - Encryption Status Section
    
    private var encryptionStatusSection: some View {
        HStack(spacing: 12) {
            // Encryption icon with animation
            Image(systemName: chat.isEncryptionReady ? "lock.shield.fill" : "lock.rotation")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            chat.isEncryptionReady ? Color.green : Color.orange,
                            (chat.isEncryptionReady ? Color.green : Color.orange).opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse, options: .repeating, isActive: chat.keyExchangeInProgress)
                .frame(width: 32, height: 32)
            
            // Text info
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.isEncryptionReady ? "End-to-End Encrypted" : "Establishing Encryption")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(chat.isEncryptionReady ? "Messages are secure" : "Exchanging keys…")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 0)
            
            // Status indicator
            if chat.keyExchangeInProgress {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    .scaleEffect(0.8)
            } else if chat.isEncryptionReady {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }
    
    // MARK: - Disconnect Section
    
    private var disconnectSection: some View {
        Button(action: { showDisconnectConfirm = true }) {
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Disconnect")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Close P2P connection")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 0)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Cancel Connection Section
    
    private var cancelConnectionSection: some View {
        Button(action: { chat.disconnect() }) {
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Stop waiting and return to viewing")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 0)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Computed Properties
    
    private var accessibilityDescription: String {
        let connectionText = !chat.isJoinedToRoom ? "Viewing mode" : 
                            chat.isP2PConnected ? chat.connectionPath.displayName : "Waiting"
        let encryptionText = chat.isEncryptionReady ? "Active" : chat.keyExchangeInProgress ? "In progress" : "None"
        return "Connection: \(connectionText). Encryption: \(encryptionText)"
    }
    
    // MARK: - Helper Functions
    
    private func iconForPath(_ path: ChatManager.ConnectionPath) -> String {
        switch path {
        case .directLAN: return "wifi"
        case .directReflexive: return "arrow.left.and.right"
        case .relayed: return "cloud"
        case .possiblyVPN: return "network.badge.shield.half.filled"
        case .unknown: return "questionmark"
        }
    }
    
    private func colorForPath(_ path: ChatManager.ConnectionPath) -> Color {
        switch path {
        case .directLAN: return .green
        case .directReflexive: return .teal
        case .relayed: return .orange
        case .possiblyVPN: return .purple
        case .unknown: return .gray
        }
    }
    
    private var latencyHint: String {
        switch chat.connectionPath {
        case .directLAN: return "Lowest latency"
        case .directReflexive: return "NAT optimized"
        case .relayed: return "Relayed (higher latency)"
        case .possiblyVPN: return "VPN may affect performance"
        case .unknown: return "Resolving path…"
        }
    }
}

#Preview {
    NavigationView {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                ConnectionIndicatorCard()
                    .environmentObject(ChatManager())
                
                Text("Liquid Glass Design")
                    .foregroundColor(.white)
            }
        }
    }
}
