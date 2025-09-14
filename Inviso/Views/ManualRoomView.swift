import SwiftUI

struct ManualRoomView: View {
    @EnvironmentObject private var chat: ChatManager
    @State private var roomId: String = ""
    @State private var goToChat = false

    var body: some View {
        VStack(spacing: 16) {
            // Connection status row
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if chat.isP2PConnected {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundColor(.green)
                        .accessibilityLabel("P2P Connected")
                }
            }
            .padding(.horizontal)

            // Room input
            VStack(alignment: .leading, spacing: 8) {
                Text("Room ID")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 10) {
                    TextField("Enter room id", text: $roomId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button(action: joinOrLeave) {
                        Label(chat.roomId.isEmpty ? "Join" : "Leave", systemImage: chat.roomId.isEmpty ? "arrow.right.circle" : "xmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(roomId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.roomId.isEmpty)
                }
            }
            .padding(.horizontal)

            // Helper description
            Text("Join a room by ID. Once another peer is present, the P2P link will establish and the chat will load.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Spacer()

            // Hidden navigation trigger when P2P is up
            NavigationLink(destination: ChatView(), isActive: $goToChat) { EmptyView() }
                .hidden()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Manual Room")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    .onChange(of: chat.isP2PConnected) { _ in /* ChatView shows state; no nav needed here */ }
        .onAppear {
            // Keep status fresh; auto-connect WS in background if needed when typing
            if chat.connectionStatus == .disconnected { chat.connect() }
            chat.isEphemeral = true
        }
        .onDisappear { chat.isEphemeral = false }
    }

    private var statusText: String {
        if !chat.roomId.isEmpty {
            return chat.isP2PConnected ? "In room • P2P ready" : "In room • waiting for peer…"
        }
        return chat.connectionStatus.rawValue
    }
    private var statusColor: Color {
        switch chat.connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    private func joinOrLeave() {
        if chat.roomId.isEmpty {
            let id = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return }
            chat.joinRoom(roomId: id)
            // Navigate to ChatView immediately; it will show waiting state
            goToChat = true
        } else {
            chat.leave()
        }
    }
}

#Preview {
    NavigationView { ManualRoomView().environmentObject(ChatManager()) }
}
