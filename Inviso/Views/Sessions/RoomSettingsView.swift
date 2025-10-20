//
//  RoomSettingsView.swift
//  Inviso
//
//  Modern, minimalistic room settings view for renaming and managing sessions
//

import SwiftUI

struct RoomSettingsView: View {
    @EnvironmentObject private var chat: ChatManager
    @Environment(\.dismiss) private var dismiss
    
    let session: ChatSession
    
    @State private var roomName: String = ""
    @State private var showDeleteConfirm = false
    @FocusState private var isNameFieldFocused: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with room code
                headerSection
                
                // Room Name Section
                nameSection
                
                // Info Section
                infoSection
                
                // Retention Policy
                retentionSection

                // Danger Zone
                dangerZoneSection
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Room Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            roomName = session.name ?? ""
        }
        .alert("Delete Session?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let rid = session.roomId {
                    Task {
                        await chat.deleteRoomOnServer(roomId: rid)
                        await MainActor.run {
                            chat.removeSession(session)
                            dismiss()
                        }
                    }
                } else {
                    chat.removeSession(session)
                    dismiss()
                }
            }
        } message: {
            if session.roomId != nil {
                Text("This will permanently delete the room from the server and remove it from your device. This cannot be undone.")
            } else {
                Text("This will remove the session from your device.")
            }
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 28))
                    .foregroundColor(statusColor)
            }
            
            Text(session.displayName)
                .font(.title2.weight(.bold))
                .foregroundColor(.primary)
            
            // Status badge
            Text(session.status.displayText)
                .font(.caption.weight(.semibold))
                .foregroundColor(statusColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(statusColor.opacity(0.15))
                )
        }
        .padding(.vertical, 8)
    }
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Room Name")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                HStack {
                    TextField("Enter room name", text: $roomName)
                        .focused($isNameFieldFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: roomName) { _, newValue in
                            // Auto-save on change with debounce
                            saveNameDebounced(newValue)
                        }
                    
                    if !roomName.isEmpty {
                        Button {
                            roomName = ""
                            chat.renameSession(session, newName: nil)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            Text("Give this room a memorable name")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        }
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Information")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                // Join Code
                infoRow(
                    icon: session.status == .accepted || session.status == .closed ? "checkmark.circle" : "number",
                    title: "Join Code",
                    value: session.status == .accepted || session.status == .closed ? "\(session.code) (Used)" : session.code,
                    showDivider: true
                )
                
                // Room ID (if accepted)
                if let rid = session.roomId {
                    infoRow(
                        icon: "key",
                        title: "Room ID",
                        value: String(rid.prefix(24)) + (rid.count > 24 ? "..." : ""),
                        showDivider: true,
                        monospaced: true
                    )
                }
                
                // Created date (only for creators)
                if session.isCreatedByMe {
                    infoRow(
                        icon: "calendar",
                        title: "Created",
                        value: formatAbsoluteDate(session.createdAt),
                        showDivider: true
                    )
                    
                    // First Connected (only for creators with accepted sessions)
                    if let firstConnected = session.firstConnectedAt {
                        infoRow(
                            icon: "link",
                            title: "First Connected",
                            value: formatAbsoluteDate(firstConnected),
                            showDivider: true
                        )
                    }
                } else {
                    // First Joined (for joiners - uses createdAt since that's when they joined)
                    infoRow(
                        icon: "link",
                        title: "First Joined",
                        value: formatAbsoluteDate(session.firstConnectedAt ?? session.createdAt),
                        showDivider: true
                    )
                }
                
                // Expiration (if applicable)
                if let expires = session.expiresAt {
                    infoRow(
                        icon: session.status == .expired ? "clock.badge.xmark" : "hourglass",
                        title: session.status == .expired ? "Expired" : "Expires",
                        value: formatAbsoluteDate(expires),
                        showDivider: true,
                        valueColor: session.status == .expired ? .red : nil
                    )
                }
                
                // Closed date (if applicable)
                if let closedDate = session.closedAt {
                    infoRow(
                        icon: "xmark.circle",
                        title: "Closed",
                        value: formatAbsoluteDate(closedDate),
                        showDivider: true
                    )
                }
                
                // Last activity
                infoRow(
                    icon: "clock.arrow.circlepath",
                    title: "Last Activity",
                    value: formatDate(session.lastActivityDate),
                    showDivider: true
                )
                
                // Role
                infoRow(
                    icon: session.isCreatedByMe ? "person.badge.plus" : "person.badge.key",
                    title: "Role",
                    value: session.isCreatedByMe ? "Creator" : "Joiner",
                    showDivider: true
                )
                
                // Device ID
                infoRow(
                    icon: "iphone",
                    title: "Device ID",
                    value: String(session.ephemeralDeviceId.prefix(12)) + "...",
                    showDivider: false,
                    monospaced: true
                )
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Danger Zone")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.red)
                .padding(.horizontal, 4)
            
            // Single delete button
            Button {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                    Text(session.roomId != nil ? "Delete Session" : "Remove Session")
                        .font(.body.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.red)
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Helper Views
    
    private func infoRow(icon: String, title: String, value: String, showDivider: Bool, valueColor: Color? = nil, monospaced: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(value)
                    .font(monospaced ? .body.monospaced() : .body)
                    .foregroundColor(valueColor ?? .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding()
            
            if showDivider {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }

    private var retentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Message Retention")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                // Picker for retention policy
                Picker(selection: Binding(
                    get: { chat.currentRetentionPolicy },
                    set: { newPolicy in
                        chat.updateRetentionPolicy(newPolicy)
                    }
                ), label: Text("Retention")) {
                    ForEach(MessageRetentionPolicy.allCases, id: \.self) { policy in
                        HStack {
                            Image(systemName: policy.icon)
                            Text(policy.displayName)
                        }
                        .tag(policy)
                    }
                }
                .pickerStyle(.menu)

                // Show peer policy if available
                if let peer = chat.peerRetentionPolicy {
                    HStack {
                        Text("Peer preference:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(peer.displayName)
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                }

                // Delete all stored messages
                Button {
                    chat.deleteAllMessages()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete All Saved Messages")
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusIcon: String {
        switch session.status {
        case .pending: return "hourglass"
        case .accepted: return "checkmark.circle.fill"
        case .closed: return "xmark.circle"
        case .expired: return "clock.badge.xmark"
        }
    }
    
    private var statusColor: Color {
        switch session.status {
        case .pending: return .yellow
        case .accepted: return .green
        case .closed: return .gray
        case .expired: return .red
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatAbsoluteDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func saveNameDebounced(_ newName: String) {
        // Cancel previous save task
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        
        // Schedule new save after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak chat] in
            guard let chat = chat else { return }
            let sessionToUpdate = chat.sessions.first(where: { $0.id == self.session.id })
            if let sessionToUpdate = sessionToUpdate {
                chat.renameSession(sessionToUpdate, newName: newName.isEmpty ? nil : newName)
            }
        }
    }
}

// MARK: - Status Extension
extension SessionStatus {
    var displayText: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Active"
        case .closed: return "Closed"
        case .expired: return "Expired"
        }
    }
}

#Preview {
    NavigationView {
        RoomSettingsView(session: ChatSession(
            name: "Project Meeting",
            code: "123456",
            roomId: "abc123def456",
            createdAt: Date().addingTimeInterval(-3600),
            expiresAt: Date().addingTimeInterval(7200),
            status: .accepted,
            isCreatedByMe: true
        ))
        .environmentObject(ChatManager())
    }
}
