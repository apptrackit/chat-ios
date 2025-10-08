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
    @State private var goToChat = false
    @State private var goToPending = false
    @State private var renamingSession: ChatSession? = nil
    @State private var renameText: String = ""
    @State private var isVisible = false
    @State private var ticker = Timer.publish(every: 6.0, on: .main, in: .common).autoconnect()
    @State private var showQRForSession: ChatSession? = nil
    @State private var showAboutForSession: ChatSession? = nil
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
            .navigationDestination(isPresented: $goToPending) {
                if let pendingSession = pendingSelectedSession {
                    PendingSessionView(session: pendingSession)
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
                    // Contacts (sorted dynamically)
                    if !activeSessions.isEmpty {
                        Section {
                            ForEach(activeSessions, id: \.id) { session in
                                sessionRow(session)
                            }
                        } header: {
                            HStack {
                                Text("Contacts")
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
                    }
                }
                .listStyle(.insetGrouped)
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
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showQRForSession != nil)
        .onChange(of: chat.sessions) {
            // Auto-close QR modal when session becomes accepted or expired
            if let qrSession = showQRForSession {
                if let updated = chat.sessions.first(where: { $0.id == qrSession.id }) {
                    if updated.status == .accepted || updated.status == .expired {
                        withAnimation(.spring()) { showQRForSession = nil }
                    }
                }
            }
        }
        .sheet(item: $showAboutForSession) { sess in
            NavigationView {
                SessionAboutView(session: sess)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showAboutForSession = nil } } }
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
    }
    
    // MARK: - Session Categorization
    
    private var activeSessions: [ChatSession] {
        let filtered = chat.sessions.filter { $0.status == .pending || $0.status == .accepted }
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
            .filter { $0.status == .closed || $0.status == .expired }
            .sorted { $0.lastActivityDate > $1.lastActivityDate }
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
                goToPending = true
            } else if let rid = session.roomId { // accepted
                chat.joinRoom(roomId: rid)
                goToChat = true
            }
        } label: {
            HStack(spacing: 12) {
                statusDot(for: session)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName)
                        .font(.body.weight(.semibold))
                    subtitleView(for: session)
                }
                Spacer()
                if session.status == .pending {
                    Button {
                        showQRForSession = session
                    } label: {
                        Image(systemName: "qrcode")
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .buttonStyle(.plain)
        .disabled(chat.connectionStatus != .connected && session.status != .pending)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                chat.removeSession(session)
            } label: { 
                Image(systemName: "trash")
            }
        }
        .contextMenu {
            Button {
                promptRename(session)
            } label: { Label("Rename", systemImage: "pencil") }
            Button {
                showAboutForSession = session
            } label: { Label("About", systemImage: "info.circle") }
            if let rid = session.roomId {
                Button(role: .destructive) {
                    Task { await chat.deleteRoomOnServer(roomId: rid) }
                } label: { Label("Delete on server", systemImage: "xmark.bin") }
            }
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

    private var pendingSelectedSession: ChatSession? {
        guard goToPending, let id = chat.activeSessionId else { return nil }
        return chat.sessions.first(where: { $0.id == id })
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
}

#Preview {
    NavigationView { SessionsView() }
}
