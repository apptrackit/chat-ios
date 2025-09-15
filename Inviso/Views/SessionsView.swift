import SwiftUI
import UIKit

struct SessionsView: View {
    @EnvironmentObject private var chat: ChatManager
    @State private var goToChat = false
    @State private var goToPending = false

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
                                goToChat = true
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

#Preview {
    NavigationView { SessionsView() }
}
