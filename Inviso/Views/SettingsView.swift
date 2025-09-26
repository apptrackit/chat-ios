import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var chat: ChatManager
    @State private var deviceID: String = DeviceIDManager.shared.id
    @State private var showResetConfirm: Bool = false
    @State private var showEraseConfirm: Bool = false
    @State private var isErasing: Bool = false
    @ObservedObject private var serverConfig = ServerConfig.shared
    @State private var editServerHost: String = ServerConfig.shared.host
    @State private var showServerChangeAlert = false
    @ObservedObject private var authStore = AuthenticationSettingsStore.shared
    @State private var requireBiometric = AuthenticationSettingsStore.shared.settings.mode.requiresBiometrics
    @State private var requirePassphrase = AuthenticationSettingsStore.shared.settings.mode.requiresPassphrase
    @State private var hasPassphrase = PassphraseManager.shared.hasPassphrase
    @State private var biometricCapability = BiometricAuth.shared.capability()
    @State private var showPassphraseSheet = false
    @State private var pendingPassphraseIntent: PassphraseIntent?
    @State private var passphraseErrorMessage: String?
    @State private var isApplyingAuthChange = false
    @State private var showRemovePassphraseConfirm = false

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

            securitySection

            Section(header: Text("About")) {
                HStack {
                    Text("Server")
                    Spacer()
                    HStack(spacing: 4) {
                        Text(serverConfig.host)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { editServerHost = serverConfig.host; showServerChangeAlert = true }
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
        .alert("Change Server", isPresented: $showServerChangeAlert) {
            TextField("Host", text: $editServerHost)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let newHost = editServerHost
                chat.changeServerHost(to: newHost)
            }
        } message: {
            Text("Enter server host (e.g. chat.example.com). Current: \(serverConfig.host)")
        }
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
            syncAuthState()
            biometricCapability = BiometricAuth.shared.capability()
        }
        .onReceive(authStore.$settings) { _ in syncAuthState() }
        .alert("Authentication Error", isPresented: Binding(get: { passphraseErrorMessage != nil }, set: { if !$0 { passphraseErrorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(passphraseErrorMessage ?? "")
        }
        .alert("Remove Passphrase?", isPresented: $showRemovePassphraseConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                removePassphrase()
            }
        } message: {
            Text("This deletes the stored passphrase and disables passphrase authentication.")
        }
        .sheet(isPresented: $showPassphraseSheet, onDismiss: handlePassphraseSheetDismiss) {
            if let intent = pendingPassphraseIntent {
                PassphraseSetupView(
                    mode: intent == .change ? .change : .create,
                    onComplete: handlePassphraseSet(_:),
                    onCancel: handlePassphraseCancel
                )
            }
        }
    }
}

#Preview {
    NavigationView { SettingsView() }
        .environmentObject(ChatManager())
}

// MARK: - Erase helpers
extension SettingsView {
    private enum PassphraseIntent {
        case enable
        case change
    }

    private var passphraseManager: PassphraseManager { .shared }

    @ViewBuilder
    private var securitySection: some View {
        Section(header: Text("Security")) {
            Toggle(isOn: Binding(get: { requireBiometric }, set: { updateBiometricToggle($0) })) {
                Label("Require \(biometricCapability.localizedName)", systemImage: biometricCapability.systemImageName)
            }
            .disabled(biometricCapability == .none)
            if biometricCapability == .none {
                Text("Biometric authentication isn't available on this device.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Toggle(isOn: Binding(get: { requirePassphrase }, set: { updatePassphraseToggle($0) })) {
                Label("Require Passphrase", systemImage: "key.fill")
            }

            Button(hasPassphrase ? "Change Passphrase" : "Set Passphrase") {
                pendingPassphraseIntent = hasPassphrase ? .change : .enable
                showPassphraseSheet = true
            }
            .buttonStyle(.borderless)

            if hasPassphrase {
                Button("Remove Passphrase", role: .destructive) {
                    showRemovePassphraseConfirm = true
                }
                .buttonStyle(.borderless)
            }

            Label(hasPassphrase ? "Passphrase configured" : "No passphrase set", systemImage: hasPassphrase ? "checkmark.seal.fill" : "exclamationmark.triangle")
                .foregroundColor(hasPassphrase ? .secondary : .orange)
                .font(.footnote)

            Text("Authentication is required whenever the app returns to the foreground.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func syncAuthState() {
        isApplyingAuthChange = true
        let mode = authStore.settings.mode
        requireBiometric = mode.requiresBiometrics
        requirePassphrase = mode.requiresPassphrase
        hasPassphrase = passphraseManager.hasPassphrase
        isApplyingAuthChange = false
    }

    private func updateBiometricToggle(_ newValue: Bool) {
        guard !isApplyingAuthChange else { return }
        if newValue && biometricCapability == .none {
            requireBiometric = false
            passphraseErrorMessage = "This device doesn't support biometrics."
            return
        }
        applyAuthenticationMode(biometric: newValue, passphrase: requirePassphrase)
    }

    private func updatePassphraseToggle(_ newValue: Bool) {
        guard !isApplyingAuthChange else { return }
        if newValue {
            guard hasPassphrase else {
                pendingPassphraseIntent = .enable
                showPassphraseSheet = true
                DispatchQueue.main.async { requirePassphrase = false }
                return
            }
        } else {
            applyAuthenticationMode(biometric: requireBiometric, passphrase: false)
            return
        }
        applyAuthenticationMode(biometric: requireBiometric, passphrase: newValue)
    }

    private func removePassphrase() {
        passphraseManager.clear()
        passphraseErrorMessage = nil
        hasPassphrase = passphraseManager.hasPassphrase
        if requirePassphrase {
            requirePassphrase = false
        }
        applyAuthenticationMode(biometric: requireBiometric, passphrase: false)
    }

    private func applyAuthenticationMode(biometric: Bool, passphrase: Bool) {
        let newMode: AuthenticationSettings.Mode
        switch (biometric, passphrase) {
        case (true, true): newMode = .both
        case (true, false): newMode = .biometricOnly
        case (false, true): newMode = .passphraseOnly
        default: newMode = .disabled
        }
        authStore.update { $0.mode = newMode }
    }

    private func handlePassphraseSet(_ passphrase: String) {
        do {
            try passphraseManager.setPassphrase(passphrase)
            hasPassphrase = true
            if pendingPassphraseIntent == .enable {
                requirePassphrase = true
                applyAuthenticationMode(biometric: requireBiometric, passphrase: true)
            }
            pendingPassphraseIntent = nil
            showPassphraseSheet = false
        } catch {
            passphraseErrorMessage = "Unable to store passphrase securely."
        }
    }

    private func handlePassphraseCancel() {
        pendingPassphraseIntent = nil
        showPassphraseSheet = false
    }

    private func handlePassphraseSheetDismiss() {
        pendingPassphraseIntent = nil
    }

    private func eraseAll(deviceId: String) async {
        await purgeServer(deviceId: deviceId)
        await clearLocalStores()
        await MainActor.run {
            syncAuthState()
        }
    }

    private func purgeServer(deviceId: String) async {
    guard let url = URL(string: "https://\(ServerConfig.shared.host)/api/user/purge") else { return }
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

    private func clearLocalStores() async {
        PassphraseManager.shared.clear()
        await MainActor.run {
            AuthenticationSettingsStore.shared.reset()
        }
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
