import SwiftUI
import UIKit

struct SessionsView: View {
    @EnvironmentObject private var chat: ChatManager
    @State private var goToChat = false
    @State private var goToPending = false
    @State private var renamingSession: ChatSession? = nil
    @State private var renameText: String = ""

    var body: some View {
        content
            .background(
                Group {
                    NavigationLink(destination: ChatView(), isActive: $goToChat) { EmptyView() }.hidden()
                    if let pendingSession = pendingSelectedSession {
                        NavigationLink(destination: PendingSessionView(session: pendingSession), isActive: $goToPending) { EmptyView() }.hidden()
                    }
                }
            )
            .navigationTitle("Sessions")
            .signalingToolbar()
            .onAppear {
                if chat.connectionStatus == .disconnected { chat.connect() }
                chat.pollPendingAndValidateRooms()
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
                    ForEach(chat.sessions, id: \.id) { session in
                        Button {
                            chat.selectSession(session)
                            if session.status == .pending {
                                goToPending = true
                            } else {
                                // If accepted and has roomId, join
                                if let rid = session.roomId {
                                    chat.joinRoom(roomId: rid)
                                    goToChat = true
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                statusDot(for: session)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.displayName)
                                        .font(.body.weight(.semibold))
                                    Text(subtitle(for: session))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(Color(UIColor.tertiaryLabel))
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                chat.removeSession(session)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        .contextMenu {
                            Button {
                                promptRename(session)
                            } label: { Label("Rename", systemImage: "pencil") }
                            if let rid = session.roomId {
                                Button(role: .destructive) {
                                    Task { await chat.deleteRoomOnServer(roomId: rid) }
                                } label: { Label("Delete on server", systemImage: "xmark.bin") }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func statusDot(for s: ChatSession) -> some View {
        let color: Color = {
            switch s.status {
            case .pending: return .yellow
            case .accepted: return .green
            case .closed: return .gray
            }
        }()
        return Circle().fill(color).frame(width: 10, height: 10)
    }

    private func subtitle(for s: ChatSession) -> String {
        switch s.status {
        case .pending:
            return "Waiting • Code \(s.code)"
        case .accepted:
            return "Active"
        case .closed:
            return "Closed"
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
        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
    }
}

#Preview {
    NavigationView { SessionsView() }
}
