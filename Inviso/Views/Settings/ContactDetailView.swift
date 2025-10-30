//
//  ContactDetailView.swift
//  Inviso
//
//  Detailed view showing all information about a contact/session.
//  Displays encryption status, message statistics, and session metadata.
//

import SwiftUI

struct ContactDetailView: View {
    let session: ChatSession
    @EnvironmentObject private var chat: ChatManager
    @State private var messageStats: MessageStats?
    @State private var showDeleteConfirm = false
    @State private var isLoading = true
    
    struct MessageStats {
        var totalCount: Int = 0
        var textCount: Int = 0
        var locationCount: Int = 0
        var voiceCount: Int = 0
        var oldestMessage: Date?
        var newestMessage: Date?
        var totalStorageSize: Int64 = 0
        var isEncrypted: Bool = true
    }
    
    var body: some View {
        List {
            // Basic Information
            Section(header: Label("Basic Information", systemImage: "info.circle.fill")) {
                DetailRow(
                    icon: "person.fill",
                    iconColor: .blue,
                    title: "Display Name",
                    value: session.displayName
                )
                
                DetailRow(
                    icon: "number",
                    iconColor: .purple,
                    title: "Room Code",
                    value: session.code,
                    isCopyable: true
                )
                
                DetailRow(
                    icon: "calendar",
                    iconColor: .orange,
                    title: "Created",
                    value: formatDate(session.createdAt)
                )
                
                DetailRow(
                    icon: "clock.fill",
                    iconColor: .green,
                    title: "Last Activity",
                    value: formatDate(session.lastActivityDate)
                )
                
                if let firstConnected = session.firstConnectedAt {
                    DetailRow(
                        icon: "link.circle.fill",
                        iconColor: .blue,
                        title: "First Connected",
                        value: formatDate(firstConnected)
                    )
                }
                
                if let closedAt = session.closedAt {
                    DetailRow(
                        icon: "xmark.circle.fill",
                        iconColor: .red,
                        title: "Closed",
                        value: formatDate(closedAt)
                    )
                }
            }
            
            // Status Information
            Section(header: Label("Status", systemImage: "circle.hexagongrid.fill")) {
                HStack {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                        .frame(width: 24)
                    Text("Connection Status")
                    Spacer()
                    Text(session.status.rawValue.capitalized)
                        .foregroundColor(statusColor)
                        .font(.headline)
                }
                
                DetailRow(
                    icon: "arrow.up.doc.fill",
                    iconColor: .blue,
                    title: "Session Role",
                    value: session.isCreatedByMe ? "Creator" : "Joiner"
                )
                
                if let wasInitiator = session.wasOriginalInitiator {
                    DetailRow(
                        icon: "person.badge.key.fill",
                        iconColor: .purple,
                        title: "Original Role",
                        value: wasInitiator ? "Initiator" : "Responder"
                    )
                }
                
                if session.isPinned {
                    HStack {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.yellow)
                            .frame(width: 24)
                        Text("Pinned")
                        Spacer()
                        if let order = session.pinnedOrder {
                            Text("Position \(order)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Encryption & Security
            Section(header: Label("Security", systemImage: "lock.shield.fill")) {
                HStack {
                    Image(systemName: session.encryptionEnabled ? "lock.fill" : "lock.open.fill")
                        .foregroundColor(session.encryptionEnabled ? .green : .red)
                        .frame(width: 24)
                    Text("End-to-End Encryption")
                    Spacer()
                    Text(session.encryptionEnabled ? "Enabled" : "Disabled")
                        .foregroundColor(session.encryptionEnabled ? .green : .red)
                        .font(.headline)
                }
                
                if let keyExchange = session.keyExchangeCompletedAt {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Key Exchange Completed")
                            Text(formatDate(keyExchange))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                    }
                }
                
                DetailRow(
                    icon: "eye.slash.fill",
                    iconColor: .indigo,
                    title: "Ephemeral Device ID",
                    value: String(session.ephemeralDeviceId.prefix(12)) + "...",
                    subtitle: "Unique privacy identifier for this session"
                )
                
                if let roomId = session.roomId {
                    DetailRow(
                        icon: "server.rack",
                        iconColor: .blue,
                        title: "Room ID",
                        value: String(roomId.prefix(16)) + "...",
                        isCopyable: true
                    )
                }
            }
            
            // Message Storage
            Section(header: Label("Message Storage", systemImage: "archivebox.fill")) {
                HStack {
                    Image(systemName: session.messageLifetime.icon)
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text("Retention Policy")
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(session.messageLifetime.displayName)
                            .font(.headline)
                        if session.messageLifetime == .ephemeral {
                            Text("Not saved to disk")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Encrypted on device")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                if session.lifetimeAgreedByBoth, let agreedAt = session.lifetimeAgreedAt {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Policy Agreed")
                            Text("Both peers confirmed on \(formatDate(agreedAt))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if session.messageLifetime != .ephemeral {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        Text("Pending Agreement")
                            .foregroundColor(.orange)
                    }
                }
                
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading message statistics...")
                            .foregroundColor(.secondary)
                    }
                } else if let stats = messageStats, stats.totalCount > 0 {
                    DetailRow(
                        icon: "message.fill",
                        iconColor: .blue,
                        title: "Total Messages Saved",
                        value: "\(stats.totalCount)"
                    )
                    
                    if stats.textCount > 0 {
                        DetailRow(
                            icon: "text.bubble.fill",
                            iconColor: .green,
                            title: "Text Messages",
                            value: "\(stats.textCount)"
                        )
                    }
                    
                    if stats.locationCount > 0 {
                        DetailRow(
                            icon: "location.fill",
                            iconColor: .red,
                            title: "Location Messages",
                            value: "\(stats.locationCount)"
                        )
                    }
                    
                    if stats.voiceCount > 0 {
                        DetailRow(
                            icon: "waveform",
                            iconColor: .purple,
                            title: "Voice Messages",
                            value: "\(stats.voiceCount)"
                        )
                    }
                    
                    if let oldest = stats.oldestMessage {
                        DetailRow(
                            icon: "calendar.badge.minus",
                            iconColor: .gray,
                            title: "Oldest Message",
                            value: formatDate(oldest)
                        )
                    }
                    
                    if let newest = stats.newestMessage {
                        DetailRow(
                            icon: "calendar.badge.plus",
                            iconColor: .gray,
                            title: "Newest Message",
                            value: formatDate(newest)
                        )
                    }
                    
                    DetailRow(
                        icon: "internaldrive.fill",
                        iconColor: .orange,
                        title: "Storage Size",
                        value: formatBytes(stats.totalStorageSize),
                        subtitle: "All messages are encrypted with AES-256-GCM"
                    )
                    
                    if stats.isEncrypted {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fully Encrypted Storage")
                                    .foregroundColor(.green)
                                Text("Messages encrypted at rest with your passphrase")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundColor(.secondary)
                            .frame(width: 24)
                        Text("No messages saved")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Notifications
            if !session.notifications.isEmpty {
                Section(header: Label("Notifications", systemImage: "bell.fill")) {
                    DetailRow(
                        icon: "bell.badge.fill",
                        iconColor: .red,
                        title: "Total Notifications",
                        value: "\(session.notifications.count)"
                    )
                    
                    if session.unreadNotificationCount > 0 {
                        DetailRow(
                            icon: "envelope.badge.fill",
                            iconColor: .red,
                            title: "Unread",
                            value: "\(session.unreadNotificationCount)"
                        )
                    }
                    
                    if let lastNotif = session.lastNotificationTime {
                        DetailRow(
                            icon: "clock.badge",
                            iconColor: .blue,
                            title: "Last Notification",
                            value: formatDate(lastNotif)
                        )
                    }
                }
            }
            
            // Session Metadata
            Section(header: Label("Technical Details", systemImage: "gearshape.2.fill")) {
                DetailRow(
                    icon: "number.circle.fill",
                    iconColor: .gray,
                    title: "Session ID",
                    value: session.id.uuidString,
                    isCopyable: true
                )
                
                DetailRow(
                    icon: "person.text.rectangle.fill",
                    iconColor: .indigo,
                    title: "Full Ephemeral ID",
                    value: session.ephemeralDeviceId,
                    isCopyable: true
                )
                
                if let expires = session.expiresAt {
                    DetailRow(
                        icon: "hourglass.bottomhalf.fill",
                        iconColor: .orange,
                        title: "Expires",
                        value: formatDate(expires)
                    )
                }
            }
            
            // Actions
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Delete Contact")
                    }
                }
            }
        }
        .navigationTitle(session.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadMessageStats()
        }
        .alert("Delete Contact?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteContact()
            }
        } message: {
            Text("Remove \(session.displayName) and all \(messageStats?.totalCount ?? 0) saved messages? This cannot be undone.")
        }
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
    
    private func loadMessageStats() {
        Task {
            isLoading = true
            defer { isLoading = false }
            
            guard let messages = try? MessageStorageManager.shared.loadMessages(for: session.id) else {
                await MainActor.run {
                    messageStats = nil
                }
                return
            }
            
            var stats = MessageStats()
            stats.totalCount = messages.count
            
            for message in messages {
                switch message.messageType {
                case .text:
                    stats.textCount += 1
                case .location:
                    stats.locationCount += 1
                case .voice:
                    stats.voiceCount += 1
                }
                
                // Track oldest and newest
                if stats.oldestMessage == nil || message.timestamp < stats.oldestMessage! {
                    stats.oldestMessage = message.timestamp
                }
                if stats.newestMessage == nil || message.timestamp > stats.newestMessage! {
                    stats.newestMessage = message.timestamp
                }
                
                // Calculate storage size (approximate)
                stats.totalStorageSize += Int64(message.encryptedContent.count + message.nonce.count + message.tag.count)
            }
            
            stats.isEncrypted = session.encryptionEnabled
            
            await MainActor.run {
                messageStats = stats
            }
        }
    }
    
    private func deleteContact() {
        Task {
            // Delete stored messages
            try? MessageStorageManager.shared.deleteMessages(for: session.id)
            
            // Remove session (this also handles ephemeral ID cleanup and server purge)
            await MainActor.run {
                chat.removeSession(session)
                
                // Navigate back
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let navigationController = window.rootViewController as? UINavigationController {
                    navigationController.popViewController(animated: true)
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Detail Row Component

struct DetailRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    var subtitle: String?
    var isCopyable: Bool = false
    
    @State private var showCopied = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.body)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                
                if showCopied {
                    Text("Copied!")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            if isCopyable {
                Button {
                    UIPasteboard.general.string = value
                    withAnimation {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showCopied = false
                        }
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let sampleSession = ChatSession(
        id: UUID(),
        name: "John Doe",
        code: "123456",
        roomId: "room-abc-123",
        createdAt: Date().addingTimeInterval(-86400 * 7),
        lastActivityDate: Date().addingTimeInterval(-3600),
        firstConnectedAt: Date().addingTimeInterval(-86400 * 6),
        status: .accepted,
        isCreatedByMe: true,
        encryptionEnabled: true,
        keyExchangeCompletedAt: Date().addingTimeInterval(-86400 * 6),
        isPinned: true,
        pinnedOrder: 1
    )
    
    NavigationView {
        ContactDetailView(session: sampleSession)
            .environmentObject(ChatManager())
    }
}

