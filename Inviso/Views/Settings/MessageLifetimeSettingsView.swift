//
//  MessageLifetimeSettingsView.swift
//  Inviso
//
//  Message retention settings popup - clean and minimal
//  One-tap to propose changes to peer
//
//  Created by GitHub Copilot on 10/26/25.
//

import SwiftUI

struct MessageLifetimeSettingsView: View {
    @ObservedObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let lifetimeOptions: [MessageLifetime] = [
        .ephemeral, .oneHour, .sixHours, .oneDay, .sevenDays, .thirtyDays
    ]
    
    private var currentLifetime: MessageLifetime {
        chatManager.activeSession?.messageLifetime ?? .ephemeral
    }
    
    private var isAgreed: Bool {
        chatManager.activeSession?.lifetimeAgreedByBoth ?? false
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Message Retention")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .padding()
            
            if !chatManager.isP2PConnected {
                // Not connected state
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    
                    Text("Not Connected")
                        .font(.headline)
                    
                    Text("Connect to a peer first")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // Connected - show options
                ScrollView {
                    VStack(spacing: 12) {
                        // Current status indicator
                        if isAgreed {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Active: \(currentLifetime.displayName)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.orange)
                                Text("Pending agreement")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Lifetime options - tappable cards
                        ForEach(lifetimeOptions, id: \.self) { lifetime in
                            LifetimeCard(
                                lifetime: lifetime,
                                isCurrent: currentLifetime == lifetime && isAgreed,
                                onTap: {
                                    if currentLifetime != lifetime {
                                        proposeLifetime(lifetime)
                                    }
                                }
                            )
                            .disabled(!chatManager.isP2PConnected)
                        }
                    }
                    .padding()
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func proposeLifetime(_ lifetime: MessageLifetime) {
        do {
            try chatManager.proposeMessageLifetime(lifetime)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// Clean card design for each lifetime option
struct LifetimeCard: View {
    let lifetime: MessageLifetime
    let isCurrent: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: lifetime.icon)
                    .font(.title2)
                    .foregroundStyle(isCurrent ? .green : .accentColor)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isCurrent ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.15))
                    )
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(lifetime.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(lifetime.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Status indicator
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isCurrent ? Color.green.opacity(0.05) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isCurrent ? Color.green.opacity(0.3) : Color(.separator).opacity(0.5),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// Shorter descriptions for cleaner UI
extension MessageLifetime {
    var shortDescription: String {
        switch self {
        case .ephemeral:
            return "Delete on exit"
        case .oneHour:
            return "1 hour"
        case .sixHours:
            return "6 hours"
        case .oneDay:
            return "24 hours"
        case .sevenDays:
            return "1 week"
        case .thirtyDays:
            return "1 month"
        }
    }
    
    var description: String {
        switch self {
        case .ephemeral:
            return "Messages deleted when you leave the chat"
        case .oneHour:
            return "Auto-delete 1 hour after sending"
        case .sixHours:
            return "Auto-delete 6 hours after sending"
        case .oneDay:
            return "Auto-delete 1 day after sending"
        case .sevenDays:
            return "Auto-delete 7 days after sending"
        case .thirtyDays:
            return "Auto-delete 30 days after sending"
        }
    }
}

#Preview {
    MessageLifetimeSettingsView(chatManager: ChatManager())
}
