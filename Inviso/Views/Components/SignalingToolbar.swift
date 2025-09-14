import SwiftUI

// Reusable top toolbar showing Settings and signaling status (dot + text in the center)
struct SignalingToolbar: ViewModifier {
    @EnvironmentObject private var chat: ChatManager

    func body(content: Content) -> some View {
        content.toolbar {
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
}

extension View {
    func signalingToolbar() -> some View { self.modifier(SignalingToolbar()) }
}
