import SwiftUI
import UIKit
import Combine

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
                    // Contacts (sorted by lastActivityDate)
                    if !activeSessions.isEmpty {
                        Section {
                            ForEach(activeSessions, id: \.id) { session in
                                sessionRow(session)
                            }
                        } header: {
                            Text("Contacts")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                                .textCase(nil)
                        }
                    }
                    
                    // Closed & Expired Sessions (sorted by lastActivityDate)
                    if !inactiveSessions.isEmpty {
                        Section {
                            ForEach(inactiveSessions, id: \.id) { session in
                                sessionRow(session)
                            }
                        } header: {
                            Text("Closed & Expired")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .sheet(item: $showQRForSession) { sess in
            NavigationView {
                VStack(spacing: 24) {
                    Text(sess.displayName)
                        .font(.headline)
                    QRCodeView(value: "inviso://join/" + sess.code, size: 240)
                        .padding()
                    Text("inviso://join/" + sess.code)
                        .font(.footnote.monospaced())
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showQRForSession = nil } } }
            }
        }
        .sheet(item: $showAboutForSession) { sess in
            NavigationView {
                SessionAboutView(session: sess)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showAboutForSession = nil } } }
            }
        }
    }
    
    // MARK: - Session Categorization
    
    private var activeSessions: [ChatSession] {
        chat.sessions
            .filter { $0.status == .pending || $0.status == .accepted }
            .sorted { $0.lastActivityDate > $1.lastActivityDate }
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
            } label: { Label("Delete", systemImage: "trash") }
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
}

#Preview {
    NavigationView { SessionsView() }
}
