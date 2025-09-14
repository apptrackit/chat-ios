import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section(header: Text("Account")) {
                HStack {
                    Text("Device ID")
                    Spacer()
                    Text(DeviceIDManager.shared.id)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Section(header: Text("About")) {
                HStack {
                    Text("App")
                    Spacer()
                    Text("Inviso")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationView { SettingsView() }
}
