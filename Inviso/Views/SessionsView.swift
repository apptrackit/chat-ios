import SwiftUI

struct SessionsView: View {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { goToChat = true }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add (Temp: Open Chat)")
                }
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
