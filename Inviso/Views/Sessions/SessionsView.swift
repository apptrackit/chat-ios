import SwiftUI
import UIKit
import Combine

enum ContactsSortMode: String {
    case lastActivity = "Last Activity"
    case created = "Created"
    
    var icon: String {
        switch self {
        case .lastActivity: return "clock.arrow.circlepath"
        case .created: return "calendar"
        }
    }
    
    mutating func toggle() {
        self = self == .lastActivity ? .created : .lastActivity
    }
}

enum SortDirection {
    case descending // Newest first
    case ascending  // Oldest first
    
    var icon: String {
        switch self {
        case .descending: return "arrow.down"
        case .ascending: return "arrow.up"
        }
    }
    
    var label: String {
        switch self {
        case .descending: return "Newest First"
        case .ascending: return "Oldest First"
        }
    }
    
    mutating func toggle() {
        self = self == .descending ? .ascending : .descending
    }
}

struct SessionsView: View {
    @EnvironmentObject private var chat: ChatManager
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var sessionNamespace
    @State private var goToChat = false
    @State private var showPendingRoomModal: ChatSession? = nil
    @State private var showRoomSettings: ChatSession? = nil
    @State private var sessionToDelete: ChatSession? = nil
    @State private var renamingSession: ChatSession? = nil
    @State private var renameText: String = ""
    @State private var isVisible = false
    @State private var ticker = Timer.publish(every: 6.0, on: .main, in: .common).autoconnect()
    @State private var showQRForSession: ChatSession? = nil
    @State private var showClearAllConfirmation = false
    @State private var contactsSortMode: ContactsSortMode = .lastActivity
    @State private var sortDirection: SortDirection = .descending

    var body: some View {
        content
            .navigationTitle("Sessions")
            .signalingToolbar()
            // Removed global scan button – scanning now only in join code context
            .onAppear {
                isVisible = true
                if chat.connectionStatus == .disconnected { chat.connect() }
                chat.pollPendingAndValidateRooms()
            }
            .onDisappear { isVisible = false }
            .onChange(of: scenePhase) {
                if isVisible && scenePhase == .active { chat.pollPendingAndValidateRooms() }
            }
            .navigationDestination(isPresented: $goToChat) {
                ChatView()
            }
            .onChange(of: chat.shouldNavigateToChat) { oldValue, newValue in
                if newValue {
                    print("[SessionsView] 🚀 Push notification triggered - navigating to chat")
                    goToChat = true
                    // Reset the flag
                    chat.shouldNavigateToChat = false
                }
            }
            .onChange(of: chat.shouldNavigateToSessions) { oldValue, newValue in
                if newValue {
                    print("[SessionsView] 📋 Push notification triggered - staying on sessions view")
                    // We're already on sessions view, just reset the flag
                    // The activeSessionId is already set, so the session will be highlighted
                    chat.shouldNavigateToSessions = false
                }
            }
            .onReceive(ticker) { _ in
                if isVisible && scenePhase == .active { chat.pollPendingAndValidateRooms() }
            }
    }

    private var content: some View {
        Group {
            if chat.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No sessions yet")
                        .font(.headline)
                    Text("Create or join a room using the + button.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Pinned Sessions (with drag-to-reorder)
                    if !pinnedSessions.isEmpty {
                        Section {
                            ForEach(pinnedSessions, id: \.id) { session in
                                sessionRow(session)
                                    .matchedGeometryEffect(id: session.id, in: sessionNamespace)
                            }
                            .onMove { source, destination in
                                chat.movePinnedSession(from: source, to: destination, in: pinnedSessions)
                            }
                        } header: {
                            HStack(spacing: 8) {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                                Text("Pinned")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .textCase(nil)
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Pending Sessions (only shown if there are any)
                    if !pendingSessions.isEmpty {
                        Section {
                            ForEach(pendingSessions, id: \.id) { session in
                                sessionRow(session)
                                    .matchedGeometryEffect(id: session.id, in: sessionNamespace)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                    ))
                            }
                        } header: {
                            HStack(spacing: 8) {
                                Image(systemName: "hourglass")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                                Text("Pending")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .textCase(nil)
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Active Contacts (sorted dynamically)
                    if !acceptedSessions.isEmpty {
                        Section {
                            ForEach(acceptedSessions, id: \.id) { session in
                                sessionRow(session)
                                    .matchedGeometryEffect(id: session.id, in: sessionNamespace)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .scale(scale: 0.8).combined(with: .opacity)
                                    ))
                            }
                        } header: {
                            HStack {
                                Text("Active")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .textCase(nil)
                                
                                Spacer()
                                
                                HStack(spacing: 6) {
                                    // Sort Mode Button
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            contactsSortMode.toggle()
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: contactsSortMode.icon)
                                                .font(.caption)
                                            Text(contactsSortMode.rawValue)
                                                .font(.caption.weight(.medium))
                                        }
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(Color.accentColor.opacity(0.12))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .transition(.scale.combined(with: .opacity))
                                    
                                    // Sort Direction Button
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            sortDirection.toggle()
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(sortDirection.label)
                                                .font(.caption.weight(.medium))
                                            Image(systemName: sortDirection.icon)
                                                .font(.caption2.weight(.bold))
                                        }
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(Color.accentColor.opacity(0.12))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.trailing, 4)
                        }
                    }
                    
                    // Closed & Expired Sessions (sorted by lastActivityDate)
                    if !inactiveSessions.isEmpty {
                        Section {
                            ForEach(inactiveSessions, id: \.id) { session in
                                sessionRow(session)
                                    .matchedGeometryEffect(id: session.id, in: sessionNamespace)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .scale(scale: 0.7).combined(with: .opacity)
                                    ))
                            }
                        } header: {
                            HStack {
                                Text("Closed & Expired")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .textCase(nil)
                                
                                Spacer()
                                
                                Button {
                                    showClearAllConfirmation = true
                                } label: {
                                    Text("Clear All")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.red)
                                        .textCase(nil)
                                }
                            }
                            .padding(.trailing, 4)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .listStyle(.insetGrouped)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: pendingSessions.map { $0.id })
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: acceptedSessions.map { $0.id })
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: inactiveSessions.map { $0.id })
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .overlay {
            if let sess = showQRForSession {
                QRCodeModal(session: sess, isPresented: Binding(
                    get: { showQRForSession != nil },
                    set: { if !$0 { showQRForSession = nil } }
                ))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .zIndex(999)
            }
            
            if let pendingSession = showPendingRoomModal {
                PendingRoomCodeModal(
                    session: pendingSession,
                    isPresented: Binding(
                        get: { showPendingRoomModal != nil },
                        set: { if !$0 { showPendingRoomModal = nil } }
                    )
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .zIndex(1000)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showQRForSession != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showPendingRoomModal != nil)
        .onChange(of: chat.sessions) {
            // Auto-close QR modal when session becomes accepted or expired
            if let qrSession = showQRForSession {
                if let updated = chat.sessions.first(where: { $0.id == qrSession.id }) {
                    if updated.status == .accepted || updated.status == .expired {
                        withAnimation(.spring()) { showQRForSession = nil }
                    }
                }
            }
            // Auto-close pending modal when session becomes accepted
            if let pendingSession = showPendingRoomModal {
                if let updated = chat.sessions.first(where: { $0.id == pendingSession.id }) {
                    if updated.status == .accepted {
                        withAnimation(.spring()) { showPendingRoomModal = nil }
                        // Then navigate to chat
                        if let rid = updated.roomId {
                            chat.joinRoom(roomId: rid)
                            goToChat = true
                        }
                    } else if updated.status == .expired {
                        withAnimation(.spring()) { showPendingRoomModal = nil }
                    }
                }
            }
        }
        .sheet(item: $showRoomSettings) { sess in
            NavigationView {
                RoomSettingsView(session: sess)
                    .environmentObject(chat)
            }
        }
        .alert("Clear All Closed & Expired?", isPresented: $showClearAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                clearAllInactiveSessions()
            }
        } message: {
            Text("This will permanently delete all closed and expired sessions. This action cannot be undone.")
        }
        .alert("Delete Session?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    chat.removeSession(session)
                    sessionToDelete = nil
                }
            }
        } message: {
            if let session = sessionToDelete {
                Text("Are you sure you want to remove \"\(session.displayName)\" from your device?")
            }
        }
    }
    
    // MARK: - Session Categorization
    
    private var pinnedSessions: [ChatSession] {
        chat.sessions
            .filter { $0.isPinned }
            .sorted { ($0.pinnedOrder ?? Int.max) < ($1.pinnedOrder ?? Int.max) }
    }
    
    private var pendingSessions: [ChatSession] {
        chat.sessions
            .filter { $0.status == .pending && !$0.isPinned }
            .sorted { $0.createdAt > $1.createdAt } // Newest pending first
    }
    
    private var acceptedSessions: [ChatSession] {
        let filtered = chat.sessions.filter { $0.status == .accepted && !$0.isPinned }
        let sorted: [ChatSession]
        
        switch contactsSortMode {
        case .lastActivity:
            sorted = filtered.sorted { 
                sortDirection == .descending 
                    ? $0.lastActivityDate > $1.lastActivityDate 
                    : $0.lastActivityDate < $1.lastActivityDate 
            }
        case .created:
            sorted = filtered.sorted { 
                sortDirection == .descending 
                    ? $0.createdAt > $1.createdAt 
                    : $0.createdAt < $1.createdAt 
            }
        }
        
        return sorted
    }
    
    private var activeSessions: [ChatSession] {
        // Keep for backward compatibility, combines pending + accepted (excluding pinned)
        let filtered = chat.sessions.filter { ($0.status == .pending || $0.status == .accepted) && !$0.isPinned }
        let sorted: [ChatSession]
        
        switch contactsSortMode {
        case .lastActivity:
            sorted = filtered.sorted { 
                sortDirection == .descending 
                    ? $0.lastActivityDate > $1.lastActivityDate 
                    : $0.lastActivityDate < $1.lastActivityDate 
            }
        case .created:
            sorted = filtered.sorted { 
                sortDirection == .descending 
                    ? $0.createdAt > $1.createdAt 
                    : $0.createdAt < $1.createdAt 
            }
        }
        
        return sorted
    }
    
    private var inactiveSessions: [ChatSession] {
        chat.sessions
            .filter { ($0.status == .closed || $0.status == .expired) && !$0.isPinned }
            .sorted { session1, session2 in
                // Sort by the date when they became inactive (closedAt or expiresAt)
                let date1 = session1.status == .closed ? (session1.closedAt ?? session1.lastActivityDate) : (session1.expiresAt ?? session1.lastActivityDate)
                let date2 = session2.status == .closed ? (session2.closedAt ?? session2.lastActivityDate) : (session2.expiresAt ?? session2.lastActivityDate)
                return date1 > date2 // Most recently closed/expired first
            }
    }
    
    // MARK: - Session Row
    
    @ViewBuilder
    private func sessionRow(_ session: ChatSession) -> some View {
        Button {
            // Block interactions that cause network join when offline
            guard chat.connectionStatus == .connected else { return }
            // Block interaction for expired sessions
            guard session.status != .expired else { return }
            chat.selectSession(session)
            
            if session.status == .pending {
                // Show the pending room modal with code
                showPendingRoomModal = session
            } else if let rid = session.roomId {
                // Mark notifications as viewed when joining
                if session.unreadNotificationCount > 0 {
                    chat.markSessionNotificationsAsViewed(sessionId: session.id)
                }
                
                // Accepted session - join room and go to chat
                chat.joinRoom(roomId: rid)
                goToChat = true
            }
        } label: {
            if session.status == .pending {
                pendingSessionRow(session)
            } else {
                standardSessionRow(session)
            }
        }
        .buttonStyle(.plain)
        .disabled(chat.connectionStatus != .connected && session.status != .pending)
        .swipeActions(edge: .leading) {
            // Pin/Unpin action
            Button {
                if session.isPinned {
                    chat.unpinSession(session)
                } else {
                    chat.pinSession(session)
                }
            } label: {
                if session.isPinned {
                    Image(systemName: "pin.slash")
                } else {
                    Image(systemName: "pin")
                }
            }
            .tint(session.isPinned ? .orange : .accentColor)
            
            // Mark as Seen (only show if there are unread notifications)
            if session.unreadNotificationCount > 0 {
                Button {
                    chat.markSessionNotificationsAsViewed(sessionId: session.id)
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                sessionToDelete = session
            } label: { 
                Image(systemName: "trash")
            }
        }
        .contextMenu {
            if session.unreadNotificationCount > 0 {
                Button {
                    chat.markSessionNotificationsAsViewed(sessionId: session.id)
                } label: {
                    Label("Mark as Seen", systemImage: "checkmark.circle")
                }
            }
            
            Button {
                showRoomSettings = session
            } label: { 
                Label("Settings", systemImage: "gearshape")
            }
            
            Button(role: .destructive) {
                sessionToDelete = session
            } label: { 
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    // Enhanced pending session row with prominent visual style
    @ViewBuilder
    private func pendingSessionRow(_ session: ChatSession) -> some View {
        HStack(spacing: 14) {
            // Pulsing status indicator
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.2))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 12, height: 12)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
                
                HStack(spacing: 6) {
                    Text("Code: \(session.code)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    if let expires = session.expiresAt {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        CountdownTimerView(expiresAt: expires)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                // Last activity on the right
                Text(formatRelativeDate(session.lastActivityDate))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            // QR Code button
            Button {
                showQRForSession = session
            } label: {
                Image(systemName: "qrcode")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.vertical, 4)
    }
    
    // Standard row for active/closed/expired sessions
    @ViewBuilder
    private func standardSessionRow(_ session: ChatSession) -> some View {
        HStack(spacing: 12) {
            statusDot(for: session)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.displayName)
                        .font(.body.weight(.semibold))
                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                    // Notification badge
                    if session.unreadNotificationCount > 0 {
                        Text("\(session.unreadNotificationCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    }
                }
                subtitleView(for: session)
                
                // Show last notification time if there are unread notifications
                if session.unreadNotificationCount > 0, let lastNotificationTime = session.lastNotificationTime {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("Last ping: \(formatRelativeDate(lastNotificationTime))")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 2)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Spacer()
                
                // Last activity on the right
                Text(formatRelativeDate(session.lastActivityDate))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
    }
    
    // MARK: - Status Indicators

    private func statusDot(for s: ChatSession) -> some View {
        let color: Color = {
            switch s.status {
            case .pending: return .yellow
            case .accepted: return .green
            case .closed: return .gray
            case .expired: return .orange
            }
        }()
        return Circle().fill(color).frame(width: 10, height: 10)
    }

    @ViewBuilder
    private func subtitleView(for s: ChatSession) -> some View {
        HStack(spacing: 4) {
            Text(subtitleText(for: s))
                .font(.caption)
                .foregroundColor(.secondary)
            
            if s.status == .pending, let expires = s.expiresAt {
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)
                CountdownTimerView(expiresAt: expires)
            }
        }
    }
    
    private func subtitleText(for s: ChatSession) -> String {
        switch s.status {
        case .pending:
            return "Waiting • Code \(s.code)"
        case .accepted:
            return "Active"
        case .closed:
            return "Closed"
        case .expired:
            return "Expired • Code \(s.code)"
        }
    }
}


// MARK: - Rename prompt
extension SessionsView {
    private func promptRename(_ session: ChatSession) {
        renamingSession = session
        renameText = session.name ?? ""
        let alert = UIAlertController(title: "Rename Session", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Name"
            tf.text = renameText
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in renamingSession = nil }))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
            let newName = alert.textFields?.first?.text
            if let s = renamingSession { chat.renameSession(s, newName: newName?.isEmpty == true ? nil : newName) }
            renamingSession = nil
        }))
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.keyWindow?.rootViewController {
            root.present(alert, animated: true)
        }
    }
    
    private func clearAllInactiveSessions() {
        let sessionsToRemove = inactiveSessions
        for session in sessionsToRemove {
            chat.removeSession(session)
        }
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationView { SessionsView() }
}
