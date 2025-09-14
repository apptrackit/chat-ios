import SwiftUI

struct ManualRoomView: View {
    @EnvironmentObject private var chat: ChatManager
    @State private var roomId: String = ""
    @State private var goToChat = false

    var body: some View {
    VStack(spacing: 16) {
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
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .allowsHitTesting(false)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .allowsHitTesting(false)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Signaling status: \(statusText)")
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

    private var statusColor: Color {
        switch chat.connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    private var statusText: String {
        switch chat.connectionStatus {
        case .connected: return "Connected"
        case .connecting, .disconnected: return "Waiting"
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
