import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var chat: ChatManager
    @State private var deviceID: String = DeviceIDManager.shared.id
    @State private var showResetConfirm: Bool = false
    @State private var showEraseConfirm: Bool = false
    @State private var isErasing: Bool = false

    var body: some View {
        Form {
            Section(header: Text("Account")) {
                Button {
                    showResetConfirm = true
                } label: {
                    HStack {
                        Text("Device ID")
                        Spacer()
                        Text(deviceID)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("Reset Device ID…", systemImage: "arrow.counterclockwise")
                    }
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

            Section(header: Text("Danger Zone")) {
                Button(role: .destructive) {
                    showEraseConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Erase All Data")
                        if isErasing { Spacer(); ProgressView() }
                    }
                }
                .disabled(isErasing)
                .help("Removes local data and cache, purges server data for this device, and resets the device ID.")
            }
        }
        .navigationTitle("Settings")
        .alert("Reset Device ID?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                DeviceIDManager.shared.reset()
                deviceID = DeviceIDManager.shared.id
            }
        } message: {
            Text("This will generate a new device identifier. Existing sessions will stop working.")
        }
        .alert("Erase All Data?", isPresented: $showEraseConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Erase", role: .destructive) {
                let oldId = deviceID
                isErasing = true
                Task {
                // Clear in-memory and persisted UI state first so lists update immediately
                chat.eraseLocalState()
                    await eraseAll(deviceId: oldId)
                    // Finally, reset device ID
                    DeviceIDManager.shared.reset()
                    await MainActor.run {
                        deviceID = DeviceIDManager.shared.id
                        isErasing = false
                    }
                }
            }
        } message: {
            Text("This removes all local data and cache, requests server-side purge for this device, and resets the device ID. This cannot be undone.")
        }
        .onAppear {
            // Ensure we show the latest value when returning to this screen
            deviceID = DeviceIDManager.shared.id
        }
    }
}

#Preview {
    NavigationView { SettingsView() }
        .environmentObject(ChatManager())
}

// MARK: - Erase helpers
extension SettingsView {
    private func eraseAll(deviceId: String) async {
        await purgeServer(deviceId: deviceId)
        clearLocalStores()
    }

    private func purgeServer(deviceId: String) async {
        guard let url = URL(string: "https://chat.ballabotond.com/api/user/purge") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["deviceId": deviceId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("Purge server responded with status: \(http.statusCode)")
            }
        } catch {
            print("Purge server error: \(error.localizedDescription)")
        }
    }

    private func clearLocalStores() {
        // UserDefaults
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
        }
        // URLCache: clear via API (don't delete on-disk DB while in use)
        URLCache.shared.removeAllCachedResponses()
        // Temporary directory: safe to clear
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        if let items = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for url in items { try? fm.removeItem(at: url) }
        }
    }
}
