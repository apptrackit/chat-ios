//
//  MessageLifetimeSettingsView.swift
//  Inviso
//
//  Message retention settings screen
//  Only enabled when connected to peer
//
//  Created by GitHub Copilot on 10/26/25.
//

import SwiftUI

struct MessageLifetimeSettingsView: View {
    @ObservedObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedLifetime: MessageLifetime
    @State private var showingProposalConfirmation = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(chatManager: ChatManager) {
        self.chatManager = chatManager
        // Initialize with current session's lifetime or default to ephemeral
        let currentLifetime = chatManager.activeSession?.messageLifetime ?? .ephemeral
        _selectedLifetime = State(initialValue: currentLifetime)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    if !chatManager.isP2PConnected {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("Connect to a peer to configure message retention")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else if let session = chatManager.activeSession {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connected to: \(session.displayName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if session.lifetimeAgreedByBoth {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Both peers agreed")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            } else {
                                HStack {
                                    Image(systemName: "clock")
                                        .foregroundColor(.orange)
                                    Text("Waiting for peer confirmation")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Connection Status")
                }
                
                Section {
                    ForEach([MessageLifetime.ephemeral, .oneHour, .sixHours, .oneDay, .sevenDays, .thirtyDays], id: \.self) { lifetime in
                        LifetimeOptionRow(
                            lifetime: lifetime,
                            isSelected: selectedLifetime == lifetime,
                            isCurrent: chatManager.activeSession?.messageLifetime == lifetime && (chatManager.activeSession?.lifetimeAgreedByBoth ?? false)
                        ) {
                            selectedLifetime = lifetime
                        }
                        .disabled(!chatManager.isP2PConnected)
                    }
                } header: {
                    Text("Retention Policy")
                } footer: {
                    Text("Messages will be automatically deleted after the selected time. Both peers must agree on the retention policy.")
                        .font(.caption)
                }
                
                if chatManager.isP2PConnected && selectedLifetime != chatManager.activeSession?.messageLifetime {
                    Section {
                        Button {
                            showingProposalConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("Propose to Peer")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Message Retention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Propose Retention Change",
                isPresented: $showingProposalConfirmation,
                titleVisibility: .visible
            ) {
                Button("Propose \(selectedLifetime.displayName)") {
                    proposeLifetime()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Ask your peer to accept '\(selectedLifetime.displayName)' retention policy?")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func proposeLifetime() {
        do {
            try chatManager.proposeMessageLifetime(selectedLifetime)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

struct LifetimeOptionRow: View {
    let lifetime: MessageLifetime
    let isSelected: Bool
    let isCurrent: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: lifetime.icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(lifetime.displayName)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Text(lifetime.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if isSelected {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// Extension for MessageLifetime descriptions
extension MessageLifetime {
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
