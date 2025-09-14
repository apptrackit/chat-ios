import SwiftUI

// Reusable top toolbar showing Settings and signaling status (dot + text in the center)
struct SignalingToolbar: ViewModifier {
    @EnvironmentObject private var chat: ChatManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var isExpanded = false

    func body(content: Content) -> some View {
        ZStack {
            content
            // Tap background to collapse when expanded
            if isExpanded {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring()) { isExpanded = false }
                    }
            }
        }
    .onDisappear { isExpanded = false }
    .onChange(of: scenePhase) { _ in isExpanded = false }
    .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Join button (primary). First tap expands, second tap (when expanded) performs Join.
                Button {
                    withAnimation(.spring()) {
                        if isExpanded {
                            print("Join tapped")
                            isExpanded = false
                        } else {
                            isExpanded = true
                        }
                    }
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                .accessibilityLabel("Join")

                // Create button (shows when expanded)
                if isExpanded {
                    Button {
                        print("Create tapped")
                        withAnimation(.spring()) { isExpanded = false }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create")
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
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
