import SwiftUI

struct SessionsView: View {
    @EnvironmentObject private var chat: ChatManager
    @State private var goToChat = false

    var body: some View {
        content
            .background(
                NavigationLink(destination: ChatView(), isActive: $goToChat) { EmptyView() }
                    .hidden()
            )
            .navigationTitle("Sessions")
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
            .onAppear {
                if chat.connectionStatus == .disconnected { chat.connect() }
            }
    }

    private var content: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Sessions")
                .font(.headline)
            Text("Coming soon…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

private extension SessionsView {
    var statusColor: Color {
        switch chat.connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    var statusText: String {
        switch chat.connectionStatus {
        case .connected: return "Connected"
        case .connecting, .disconnected: return "Waiting"
        }
    }
}

#Preview {
    NavigationView { SessionsView() }
}
