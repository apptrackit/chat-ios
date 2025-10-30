//
//  ManageContactsView.swift
//  Inviso
//
//  Comprehensive contact management showing all session details,
//  encryption status, and saved message information.
//

import SwiftUI

struct ManageContactsView: View {
    @EnvironmentObject private var chat: ChatManager
    @State private var showClearAllConfirm = false
    @State private var contactToDelete: ChatSession?
    @State private var sortOrder: SortOrder = .lastActivity
    
    enum SortOrder: String, CaseIterable {
        case lastActivity = "Last Activity"
        case name = "Name"
        case createdDate = "Created Date"
        case messageCount = "Message Count"
    }
    
    private var sortedSessions: [ChatSession] {
        switch sortOrder {
        case .lastActivity:
            return chat.sessions.sorted { $0.lastActivityDate > $1.lastActivityDate }
        case .name:
            return chat.sessions.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        case .createdDate:
            return chat.sessions.sorted { $0.createdAt > $1.createdAt }
        case .messageCount:
            return chat.sessions.sorted { getMessageCount(for: $0) > getMessageCount(for: $1) }
        }
    }
    
    var body: some View {
        List {
            Section {
                Text("Your contacts are your secure chat sessions. Each contact has end-to-end encryption and a unique ephemeral identity.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            if chat.sessions.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Contacts Yet")
                            .font(.headline)
                        Text("Create or join a session to add contacts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: Text("Contacts (\(chat.sessions.count))")) {
                    ForEach(sortedSessions) { session in
                        NavigationLink(destination: ContactDetailView(session: session)) {
                            ContactRowView(session: session)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                contactToDelete = session
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showClearAllConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Clear All Contacts")
                        }
                    }
                }
            }
        }
        .navigationTitle("Manage Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Contact?", isPresented: Binding(
            get: { contactToDelete != nil },
            set: { if !$0 { contactToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                contactToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let session = contactToDelete {
                    deleteContact(session)
                }
            }
        } message: {
            if let session = contactToDelete {
                Text("Remove \(session.displayName) and all associated data? This cannot be undone.")
            }
        }
        .alert("Clear All Contacts?", isPresented: $showClearAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                clearAllContacts()
            }
        } message: {
            Text("This will delete all \(chat.sessions.count) contacts and their associated data.")
        }
    }
    
    private func getMessageCount(for session: ChatSession) -> Int {
        guard let messages = try? MessageStorageManager.shared.loadMessages(for: session.id) else {
            return 0
        }
        return messages.count
    }
    
    private func deleteContact(_ session: ChatSession) {
        Task {
            // Delete stored messages
            try? MessageStorageManager.shared.deleteMessages(for: session.id)
            
            // Remove session (this also handles ephemeral ID cleanup and server purge)
            await MainActor.run {
                chat.removeSession(session)
                contactToDelete = nil
            }
        }
    }
    
    private func clearAllContacts() {
        Task {
            // Delete all stored messages and sessions
            let sessionsToRemove = await MainActor.run { chat.sessions }
            
            for session in sessionsToRemove {
                try? MessageStorageManager.shared.deleteMessages(for: session.id)
            }
            
            // Remove all sessions (this also handles ephemeral ID cleanup and server purge)
            await MainActor.run {
                for session in sessionsToRemove {
                    chat.removeSession(session)
                }
            }
        }
    }
}

// MARK: - Contact Row View

struct ContactRowView: View {
    let session: ChatSession
    
    private var messageCount: Int {
        guard let messages = try? MessageStorageManager.shared.loadMessages(for: session.id) else {
            return 0
        }
        return messages.count
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.system(size: 18))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.displayName)
                        .font(.headline)
                    
                    if session.encryptionEnabled {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    
                    if session.messageLifetime != .ephemeral {
                        Image(systemName: "archivebox.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                
                Text("Code: \(session.code)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    if messageCount > 0 {
                        Label("\(messageCount) saved", systemImage: "message.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if session.status == .accepted {
                        Label(session.status.rawValue.capitalized, systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else {
                        Label(session.status.rawValue.capitalized, systemImage: statusIcon)
                            .font(.caption2)
                            .foregroundColor(statusColor)
                    }
                }
            }
            
            Spacer()
            
            if session.unreadNotificationCount > 0 {
                Text("\(session.unreadNotificationCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .cornerRadius(10)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusIcon: String {
        switch session.status {
        case .pending: return "clock.fill"
        case .accepted: return "checkmark.circle.fill"
        case .closed: return "xmark.circle.fill"
        case .expired: return "hourglass.bottomhalf.fill"
        }
    }
    
    private var statusColor: Color {
        switch session.status {
        case .pending: return .yellow
        case .accepted: return .green
        case .closed: return .gray
        case .expired: return .orange
        }
    }
}

#Preview {
    NavigationView {
        ManageContactsView()
            .environmentObject(ChatManager())
    }
}

