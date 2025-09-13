import SwiftUI

struct ManualRoomView: View {
    @State private var goToChat = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.and.pencil.and.ellipsis")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Manual Room")
                .font(.headline)
            Text("Coming soon…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .background(
            NavigationLink(destination: ChatView(), isActive: $goToChat) { EmptyView() }
                .hidden()
        )
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { goToChat = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add (Temp: Open Chat)")
            }
        }
    }
}

#Preview {
    NavigationView { ManualRoomView() }
}
