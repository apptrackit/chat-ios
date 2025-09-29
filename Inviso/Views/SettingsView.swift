import SwiftUI
import LocalAuthentication

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
    @State private var pendingPassphraseIntent: PassphraseIntent?
    @State private var passphraseErrorMessage: String?
    @State private var isApplyingAuthChange = false
    @State private var showRemovePassphraseConfirm = false
    @State private var activePassphraseModal: PassphraseModal?
    @State private var showReauthModal = false
    @State private var pendingSensitiveAction: SensitiveSecurityAction?
    @State private var reauthMode: AuthenticationSettings.Mode = .disabled
    @State private var reauthErrorMessage: String?
    @State private var isReauthBiometricInFlight = false

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
                requestReauthentication(for: .removePassphrase)
            }
        } message: {
            Text("This deletes the stored passphrase and disables passphrase authentication.")
        }
        .overlay { securityOverlay }
    }
}

#Preview {
    NavigationView { SettingsView() }
        .environmentObject(ChatManager.shared)
}

// MARK: - Erase helpers
extension SettingsView {
    private enum PassphraseIntent {
        case enable
        case change
    }

    private enum PassphraseModal {
        case create
        case change

        var title: String {
            switch self {
            case .create: return "Set Passphrase"
            case .change: return "Change Passphrase"
            }
        }

        var instruction: String {
            switch self {
            case .create: return "Choose a passphrase of at least eight characters."
            case .change: return "Enter your new passphrase."
            }
        }
    }

    private enum SensitiveSecurityAction {
        case disablePassphrase
        case disableBiometric
        case changePassphrase
        case removePassphrase

        var title: String {
            switch self {
            case .disablePassphrase: return "Disable Passphrase"
            case .disableBiometric: return "Disable Biometrics"
            case .changePassphrase: return "Change Passphrase"
            case .removePassphrase: return "Remove Passphrase"
            }
        }

        var message: String {
            switch self {
            case .disablePassphrase:
                return "Authenticate to disable passphrase protection."
            case .disableBiometric:
                return "Authenticate to disable biometric unlock."
            case .changePassphrase:
                return "Authenticate before changing your passphrase."
            case .removePassphrase:
                return "Authenticate to remove the stored passphrase."
            }
        }

        var biometricReason: String {
            switch self {
            case .disablePassphrase:
                return "Confirm to disable passphrase authentication"
            case .disableBiometric:
                return "Confirm to disable biometric authentication"
            case .changePassphrase:
                return "Confirm to change your passphrase"
            case .removePassphrase:
                return "Confirm to remove the passphrase"
            }
        }
    }

    private var passphraseManager: PassphraseManager { .shared }
    private var hasActiveOverlay: Bool { activePassphraseModal != nil || showReauthModal }

    @ViewBuilder
    private var securitySection: some View {
        Section(header: Text("Security")) {
            Toggle(isOn: Binding(get: { requireBiometric }, set: { updateBiometricToggle($0) })) {
                Label("Require \(biometricCapability.localizedName)", systemImage: biometricCapability.systemImageName)
            }
            .disabled(biometricCapability == .none || hasActiveOverlay)
            if biometricCapability == .none {
                Text("Biometric authentication isn't available on this device.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Toggle(isOn: Binding(get: { requirePassphrase }, set: { updatePassphraseToggle($0) })) {
                Label("Require Passphrase", systemImage: "key.fill")
            }
            .disabled(hasActiveOverlay)

            Button(hasPassphrase ? "Change Passphrase" : "Set Passphrase") {
                guard !hasActiveOverlay else { return }
                if hasPassphrase {
                    pendingPassphraseIntent = .change
                    requestReauthentication(for: .changePassphrase)
                } else {
                    pendingPassphraseIntent = .enable
                    activePassphraseModal = .create
                }
            }
            .buttonStyle(.borderless)
            .disabled(hasActiveOverlay)

            if hasPassphrase {
                Button("Remove Passphrase", role: .destructive) {
                    showRemovePassphraseConfirm = true
                }
                .buttonStyle(.borderless)
                .disabled(hasActiveOverlay)
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
        if newValue {
            applyAuthenticationMode(biometric: true, passphrase: requirePassphrase)
            requireBiometric = true
        } else {
            requireBiometric = true
            requestReauthentication(for: .disableBiometric)
        }
    }

    private func updatePassphraseToggle(_ newValue: Bool) {
        guard !isApplyingAuthChange else { return }
        if newValue {
            guard hasPassphrase else {
                pendingPassphraseIntent = .enable
                activePassphraseModal = .create
                DispatchQueue.main.async { requirePassphrase = false }
                return
            }
            requirePassphrase = true
            applyAuthenticationMode(biometric: requireBiometric, passphrase: true)
        } else {
            requirePassphrase = true
            requestReauthentication(for: .disablePassphrase)
            return
        }
    }

    private func performPassphraseRemoval() {
        passphraseManager.clear()
        passphraseErrorMessage = nil
        hasPassphrase = passphraseManager.hasPassphrase
        if requirePassphrase {
            requirePassphrase = false
        }
        applyAuthenticationMode(biometric: requireBiometric, passphrase: false)
        syncAuthState()
    }

    private func requestReauthentication(for action: SensitiveSecurityAction) {
        guard !hasActiveOverlay else { return }
        showRemovePassphraseConfirm = false
        pendingSensitiveAction = action
        reauthMode = authStore.settings.mode
        reauthErrorMessage = nil
        isReauthBiometricInFlight = false
        showReauthModal = true
    }

    @MainActor
    private func cancelReauthentication() {
        showReauthModal = false
        isReauthBiometricInFlight = false
        reauthErrorMessage = nil
        defer { pendingSensitiveAction = nil }

        guard let action = pendingSensitiveAction else { return }
        switch action {
        case .disablePassphrase:
            requirePassphrase = true
        case .disableBiometric:
            requireBiometric = true
        case .changePassphrase:
            pendingPassphraseIntent = nil
        case .removePassphrase:
            break
        }
    }

    @MainActor
    private func completeReauthentication() {
        showReauthModal = false
        isReauthBiometricInFlight = false
        reauthErrorMessage = nil
        guard let action = pendingSensitiveAction else { return }
        pendingSensitiveAction = nil

        switch action {
        case .disablePassphrase:
            requirePassphrase = false
            applyAuthenticationMode(biometric: requireBiometric, passphrase: false)
        case .disableBiometric:
            requireBiometric = false
            applyAuthenticationMode(biometric: false, passphrase: requirePassphrase)
        case .changePassphrase:
            pendingPassphraseIntent = .change
            activePassphraseModal = .change
        case .removePassphrase:
            performPassphraseRemoval()
        }
        syncAuthState()
    }

    private func performBiometricReauthentication() {
        guard !isReauthBiometricInFlight, pendingSensitiveAction != nil else { return }
        isReauthBiometricInFlight = true
        Task {
            NotificationCenter.default.post(name: .securityExternalAuthWillBegin, object: nil)
            defer { NotificationCenter.default.post(name: .securityExternalAuthDidEnd, object: nil) }
            let reason = pendingSensitiveAction?.biometricReason ?? "Authenticate"
            let result = await BiometricAuth.shared.authenticateAllowingDevicePasscode(
                reason: reason,
                fallbackTitle: "Enter Passcode"
            )
            await MainActor.run {
                self.isReauthBiometricInFlight = false
                switch result {
                case .success:
                    self.completeReauthentication()
                case .cancelled:
                    self.reauthErrorMessage = "Authentication was cancelled."
                case .fallback:
                    self.reauthErrorMessage = "Authentication fallback selected. Enter passphrase to continue."
                case .failed(let code):
                    if code == .biometryLockout {
                        self.reauthErrorMessage = "Biometrics are locked. Enter your passphrase instead."
                    } else {
                        self.reauthErrorMessage = "Authentication failed. Try again."
                    }
                }
            }
        }
    }

    @MainActor
    private func validateReauthPassphrase(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            reauthErrorMessage = "Passphrase cannot be empty."
            return
        }
        if passphraseManager.validate(passphrase: trimmed) {
            completeReauthentication()
        } else {
            reauthErrorMessage = "Incorrect passphrase."
        }
    }


// MARK: - Modal Views
private struct PassphraseModalView: View {
    let mode: SettingsView.PassphraseModal
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case passphrase
        case confirmation
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(mode.title)
                        .font(.title3.weight(.semibold))
                    Text(mode.instruction)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 12) {
                    SecureField("New passphrase", text: $passphrase)
                        .focused($focusedField, equals: .passphrase)
                        .textContentType(.newPassword)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .confirmation }

                    SecureField("Confirm passphrase", text: $confirmation)
                        .focused($focusedField, equals: .confirmation)
                        .textContentType(.newPassword)
                        .submitLabel(.done)
                        .onSubmit { attemptSave() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Avoid using easily guessable information.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    if let error = errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                HStack(spacing: 12) {
                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Save", action: attemptSave)
                        .buttonStyle(.borderedProminent)
                        .disabled(!isValid)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(radius: 18)
            .padding(.horizontal, 32)
        }
        .onAppear { focusedField = .passphrase }
    }

    private var isValid: Bool {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmationTrimmed = confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 8 && trimmed == confirmationTrimmed
    }

    private func attemptSave() {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmationTrimmed = confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            errorMessage = "Passphrase must be at least eight characters."
            return
        }
        guard trimmed == confirmationTrimmed else {
            errorMessage = "Passphrases do not match."
            return
        }
        errorMessage = nil
        onComplete(trimmed)
    }
}

private struct ReauthenticationModalView: View {
    let action: SettingsView.SensitiveSecurityAction
    let biometricCapability: BiometricCapability
    let allowBiometric: Bool
    let allowPassphrase: Bool
    let errorMessage: String?
    let isBiometricInFlight: Bool
    let onCancel: () -> Void
    let onBiometric: () -> Void
    let onPassphrase: (String) -> Void

    @State private var passphrase: String = ""
    @FocusState private var isPassphraseFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(action.title)
                        .font(.title3.weight(.semibold))
                    Text(action.message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if allowBiometric {
                    Button {
                        onBiometric()
                    } label: {
                        HStack {
                            Image(systemName: biometricCapability.systemImageName)
                            Text(biometricButtonLabel)
                            if isBiometricInFlight {
                                Spacer(minLength: 12)
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBiometricInFlight)
                }

                if allowPassphrase {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("Passphrase", text: $passphrase)
                            .focused($isPassphraseFocused)
                            .textContentType(.password)
                            .submitLabel(.done)
                            .onSubmit(submitPassphrase)

                        Button("Confirm with Passphrase", action: submitPassphrase)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                HStack(spacing: 12) {
                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(radius: 18)
            .padding(.horizontal, 32)
        }
        .onAppear {
            if allowPassphrase {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isPassphraseFocused = true
                }
            }
        }
    }

    private var biometricButtonLabel: String {
        switch biometricCapability {
        case .faceID:
            return "Verify with Face ID"
        case .touchID:
            return "Verify with Touch ID"
        case .none:
            return "Verify"
        }
    }

    private func submitPassphrase() {
        guard passphrase.isEmpty == false else { return }
        onPassphrase(passphrase)
    }
}
    @ViewBuilder
    private var securityOverlay: some View {
        if let modal = activePassphraseModal {
            PassphraseModalView(
                mode: modal,
                onComplete: handlePassphraseSet(_:),
                onCancel: handlePassphraseCancel
            )
        } else if showReauthModal, let action = pendingSensitiveAction {
            ReauthenticationModalView(
                action: action,
                biometricCapability: biometricCapability,
                allowBiometric: reauthMode.requiresBiometrics && biometricCapability != .none,
                allowPassphrase: hasPassphrase,
                errorMessage: reauthErrorMessage,
                isBiometricInFlight: isReauthBiometricInFlight,
                onCancel: cancelReauthentication,
                onBiometric: performBiometricReauthentication,
                onPassphrase: validateReauthPassphrase(_:)
            )
        }
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
            activePassphraseModal = nil
        } catch {
            passphraseErrorMessage = "Unable to store passphrase securely."
        }
    }

    private func handlePassphraseCancel() {
        pendingPassphraseIntent = nil
        activePassphraseModal = nil
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
