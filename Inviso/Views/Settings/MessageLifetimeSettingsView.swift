//
//  MessageLifetimeSettingsView.swift
//  Inviso
//
//  Message auto-delete settings - compact popup with confirmation
//
//  Created by GitHub Copilot on 10/26/25.
//

import SwiftUI

struct MessageLifetimeSettingsView: View {
    @ObservedObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedLifetime: MessageLifetime? = nil
    @State private var showingConfirmation = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let lifetimeOptions: [MessageLifetime] = [
        .ephemeral, .oneHour, .sixHours, .oneDay, .sevenDays, .thirtyDays
    ]
    
    private var currentLifetime: MessageLifetime {
        chatManager.activeSession?.messageLifetime ?? .ephemeral
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
            
            // Title
            Text("Change Auto Delete")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.top, 12)
                .padding(.bottom, 16)
            
            if !chatManager.isP2PConnected {
                // Not connected state
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Not Connected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 120)
            } else {
                // Grid of options
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(lifetimeOptions, id: \.self) { lifetime in
                        LifetimeOptionCell(
                            lifetime: lifetime,
                            isCurrent: currentLifetime == lifetime,
                            onTap: {
                                if currentLifetime != lifetime {
                                    selectedLifetime = lifetime
                                    showingConfirmation = true
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .confirmationDialog(
            "Propose to peer?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            if let lifetime = selectedLifetime {
                Button("Send \(lifetime.displayName)") {
                    proposeLifetime(lifetime)
                }
                Button("Cancel", role: .cancel) {
                    selectedLifetime = nil
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

// Compact cell for grid layout
struct LifetimeOptionCell: View {
    let lifetime: MessageLifetime
    let isCurrent: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: lifetime.icon)
                    .font(.title2)
                    .foregroundStyle(isCurrent ? .green : .primary)
                
                Text(lifetime.compactName)
                    .font(.caption)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? .green : .primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isCurrent ? Color.green.opacity(0.1) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isCurrent ? Color.green : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// Compact names for grid
extension MessageLifetime {
    var compactName: String {
        switch self {
        case .ephemeral:
            return "RAM"
        case .oneHour:
            return "1 Hour"
        case .sixHours:
            return "6 Hours"
        case .oneDay:
            return "1 Day"
        case .sevenDays:
            return "7 Days"
        case .thirtyDays:
            return "30 Days"
        }
    }
    
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
