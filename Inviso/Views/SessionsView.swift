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
            .signalingToolbar()
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

#Preview {
    NavigationView { SessionsView() }
}
