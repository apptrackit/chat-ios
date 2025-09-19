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
            // Removed global scan button – scanning now only in join code context
            .onAppear {
                isVisible = true
                if chat.connectionStatus == .disconnected { chat.connect() }
                chat.pollPendingAndValidateRooms()
            }
            .onDisappear { isVisible = false }
            .onChange(of: scenePhase) { _ in
                if isVisible && scenePhase == .active { chat.pollPendingAndValidateRooms() }
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
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.keyWindow?.rootViewController {
            root.present(alert, animated: true)
        }
    }
}

#Preview {
    NavigationView { SessionsView() }
}
