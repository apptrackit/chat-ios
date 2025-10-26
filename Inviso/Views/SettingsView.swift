import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject private var chat: ChatManager
    @State private var showEraseConfirm: Bool = false
    @State private var isErasing: Bool = false
    @State private var eraseConfirmText: String = ""
    @ObservedObject private var serverConfig = ServerConfig.shared
    @State private var editServerHost: String = ServerConfig.shared.host
    @State private var showServerChangeAlert = false
    @State private var serverCheckStatus: ServerCheckStatus = .idle
    @State private var serverCheckTask: Task<Void, Never>?
    @ObservedObject private var authStore = AuthenticationSettingsStore.shared
    @State private var requireBiometric = AuthenticationSettingsStore.shared.settings.mode.requiresBiometrics
    @State private var requirePasscode = AuthenticationSettingsStore.shared.settings.mode.requiresPassphrase
    @State private var hasPassphrase = PassphraseManager.shared.hasPassphrase
    @State private var biometricCapability = BiometricAuth.shared.capability()
    @State private var pendingPasscodeIntent: PasscodeIntent?
    @State private var passcodeErrorMessage: String?
    @State private var isApplyingAuthChange = false
    @State private var showRemovePasscodeConfirm = false
    @State private var activePasscodeModal: PasscodeModal?
    @State private var showReauthModal = false
    @State private var pendingSensitiveAction: SensitiveSecurityAction?
    @State private var reauthMode: AuthenticationSettings.Mode = .disabled
    @State private var reauthErrorMessage: String?
    @State private var isReauthBiometricInFlight = false
    
    enum ServerCheckStatus {
        case idle
        case checking
        case online
        case offline
        case invalid
        
        var icon: String {
            switch self {
            case .idle: return "circle"
            case .checking: return "circle.dotted"
            case .online: return "checkmark.circle.fill"
            case .offline: return "exclamationmark.circle.fill"
            case .invalid: return "xmark.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .idle: return .secondary
            case .checking: return .blue
            case .online: return .green
            case .offline: return .orange
            case .invalid: return .red
            }
        }
        
        var text: String {
            switch self {
            case .idle: return "Not checked"
            case .checking: return "Checking..."
            case .online: return "Server online"
            case .offline: return "Server offline"
            case .invalid: return "Invalid address"
            }
        }
    }

    var body: some View {
        Form {
            Section(header: Label("Privacy", systemImage: "lock.shield.fill")) {
                NavigationLink {
                    EphemeralIDsView()
                } label: {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Session Identities")
                            Text("Each session uses a unique, ephemeral ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        let count = DeviceIDManager.shared.getEphemeralIDs().count
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    }
                }
                
                NavigationLink {
                    PermissionsView()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Permissions")
                            Text("Manage app permissions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            securitySection

            Section(header: Label("About", systemImage: "info.circle.fill")) {
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
                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-")
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Label("Danger Zone", systemImage: "exclamationmark.triangle.fill")) {
                Button(role: .destructive) {
                    eraseConfirmText = ""
                    showEraseConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Erase All Data")
                        if isErasing { Spacer(); ProgressView() }
                    }
                }
                .disabled(isErasing)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showServerChangeAlert) {
            ServerChangeView(
                editServerHost: $editServerHost,
                serverCheckStatus: $serverCheckStatus,
                serverCheckTask: $serverCheckTask,
                onSave: {
                    chat.changeServerHost(to: editServerHost)
                    showServerChangeAlert = false
                }
            )
        }
        .alert("Erase All Data", isPresented: $showEraseConfirm) {
            TextField("Type CONFIRM to erase", text: $eraseConfirmText)
            Button("Cancel", role: .cancel) {
                eraseConfirmText = ""
            }
            Button("Erase Everything", role: .destructive) {
                performCompleteErase()
            }
            .disabled(eraseConfirmText != "CONFIRM")
        } message: {
            Text("This will completely reset the app: remove all data, cache, passcode, Face ID, permissions, and close the app. You'll see onboarding again on next launch.\n\nType CONFIRM to proceed.")
        }
        .onAppear {
            syncAuthState()
            biometricCapability = BiometricAuth.shared.capability()
        }
        .onReceive(authStore.$settings) { _ in syncAuthState() }
        .alert("Authentication Error", isPresented: Binding(get: { passcodeErrorMessage != nil }, set: { if !$0 { passcodeErrorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(passcodeErrorMessage ?? "")
        }
        .alert("Remove Passcode?", isPresented: $showRemovePasscodeConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                requestReauthentication(for: .removePasscode)
            }
        } message: {
            Text("This deletes the stored passcode and disables passcode authentication.")
        }
        .overlay { securityOverlay }
    }
}

#Preview {
    NavigationView { SettingsView() }
        .environmentObject(ChatManager())
}

// MARK: - Erase helpers
extension SettingsView {
    fileprivate enum PasscodeIntent {
        case enable
        case change
    }

    fileprivate enum PasscodeModal {
        case create
        case change

        var title: String {
            switch self {
            case .create: return "Set Passcode"
            case .change: return "Change Passcode"
            }
        }

        var instruction: String {
            switch self {
            case .create: return "Choose a numeric passcode (4-10 digits)."
            case .change: return "Enter your new numeric passcode (4-10 digits)."
            }
        }
    }

    fileprivate enum SensitiveSecurityAction {
        case disablePasscode
        case disableBiometric
        case changePasscode
        case removePasscode

        var title: String {
            switch self {
            case .disablePasscode: return "Disable Passcode"
            case .disableBiometric: return "Disable Biometrics"
            case .changePasscode: return "Change Passcode"
            case .removePasscode: return "Remove Passcode"
            }
        }

        var message: String {
            switch self {
            case .disablePasscode:
                return "Authenticate to disable passcode protection."
            case .disableBiometric:
                return "Authenticate to disable biometric unlock."
            case .changePasscode:
                return "Authenticate before changing your passcode."
            case .removePasscode:
                return "Authenticate to remove the stored passcode."
            }
        }

        var biometricReason: String {
            switch self {
            case .disablePasscode:
                return "Confirm to disable passcode authentication"
            case .disableBiometric:
                return "Confirm to disable biometric authentication"
            case .changePasscode:
                return "Confirm to change your passcode"
            case .removePasscode:
                return "Confirm to remove the passcode"
            }
        }
    }

    private var passcodeManager: PassphraseManager { .shared }
    private var hasActiveOverlay: Bool { activePasscodeModal != nil || showReauthModal }

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

            Toggle(isOn: Binding(get: { requirePasscode }, set: { updatePasscodeToggle($0) })) {
                Label("Require Passcode", systemImage: "key.fill")
            }
            .disabled(hasActiveOverlay)

            Button(hasPassphrase ? "Change Passcode" : "Set Passcode") {
                guard !hasActiveOverlay else { return }
                if hasPassphrase {
                    pendingPasscodeIntent = .change
                    requestReauthentication(for: .changePasscode)
                } else {
                    pendingPasscodeIntent = .enable
                    activePasscodeModal = .create
                }
            }
            .buttonStyle(.borderless)
            .disabled(hasActiveOverlay)

            if hasPassphrase {
                Button("Remove Passcode", role: .destructive) {
                    showRemovePasscodeConfirm = true
                }
                .buttonStyle(.borderless)
                .disabled(hasActiveOverlay)
            }

            Label(hasPassphrase ? "Passcode configured" : "No passcode set", systemImage: hasPassphrase ? "checkmark.seal.fill" : "exclamationmark.triangle")
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
        requirePasscode = mode.requiresPassphrase
        hasPassphrase = passcodeManager.hasPassphrase
        isApplyingAuthChange = false
    }

    private func updateBiometricToggle(_ newValue: Bool) {
        guard !isApplyingAuthChange else { return }
        if newValue && biometricCapability == .none {
            requireBiometric = false
            passcodeErrorMessage = "This device doesn't support biometrics."
            return
        }
        if newValue {
            applyAuthenticationMode(biometric: true, passcode: requirePasscode)
            requireBiometric = true
        } else {
            requireBiometric = true
            requestReauthentication(for: .disableBiometric)
        }
    }

    private func updatePasscodeToggle(_ newValue: Bool) {
        guard !isApplyingAuthChange else { return }
        if newValue {
            guard hasPassphrase else {
                pendingPasscodeIntent = .enable
                activePasscodeModal = .create
                DispatchQueue.main.async { requirePasscode = false }
                return
            }
            requirePasscode = true
            applyAuthenticationMode(biometric: requireBiometric, passcode: true)
        } else {
            requirePasscode = true
            requestReauthentication(for: .disablePasscode)
            return
        }
    }

    private func performPasscodeRemoval() {
        passcodeManager.clear()
        passcodeErrorMessage = nil
        hasPassphrase = passcodeManager.hasPassphrase
        if requirePasscode {
            requirePasscode = false
        }
        applyAuthenticationMode(biometric: requireBiometric, passcode: false)
        syncAuthState()
    }

    private func requestReauthentication(for action: SensitiveSecurityAction) {
        guard !hasActiveOverlay else { return }
        showRemovePasscodeConfirm = false
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
        case .disablePasscode:
            requirePasscode = true
        case .disableBiometric:
            requireBiometric = true
        case .changePasscode:
            pendingPasscodeIntent = nil
        case .removePasscode:
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
        case .disablePasscode:
            requirePasscode = false
            applyAuthenticationMode(biometric: requireBiometric, passcode: false)
        case .disableBiometric:
            requireBiometric = false
            applyAuthenticationMode(biometric: false, passcode: requirePasscode)
        case .changePasscode:
            pendingPasscodeIntent = .change
            activePasscodeModal = .change
        case .removePasscode:
            performPasscodeRemoval()
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
                    self.reauthErrorMessage = "Authentication fallback selected. Enter passcode to continue."
                case .failed(let code):
                    if code == .biometryLockout {
                        self.reauthErrorMessage = "Biometrics are locked. Enter your passcode instead."
                    } else {
                        self.reauthErrorMessage = "Authentication failed. Try again."
                    }
                }
            }
        }
    }

    @MainActor
    private func validateReauthPasscode(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            reauthErrorMessage = "Passcode cannot be empty."
            return
        }
        if passcodeManager.validate(passphrase: trimmed) {
            completeReauthentication()
        } else {
            reauthErrorMessage = "Incorrect passcode."
        }
    }
}

// MARK: - Modal Views
private struct PasscodeModalView: View {
    let mode: SettingsView.PasscodeModal
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    @State private var passcode = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case passcode
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
                    SecureField("New passcode", text: $passcode)
                        .focused($focusedField, equals: .passcode)
                        .textContentType(.newPassword)
                        .keyboardType(.numberPad)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .confirmation }
                        .onChange(of: passcode) { oldValue, newValue in
                            // Filter to numbers only and limit to 10 digits
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue || filtered.count > 10 {
                                passcode = String(filtered.prefix(10))
                            }
                        }

                    SecureField("Confirm passcode", text: $confirmation)
                        .focused($focusedField, equals: .confirmation)
                        .textContentType(.newPassword)
                        .keyboardType(.numberPad)
                        .submitLabel(.done)
                        .onSubmit { attemptSave() }
                        .onChange(of: confirmation) { oldValue, newValue in
                            // Filter to numbers only and limit to 10 digits
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue || filtered.count > 10 {
                                confirmation = String(filtered.prefix(10))
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Use only numbers (0-9).")
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
        .onAppear { focusedField = .passcode }
    }

    private var isValid: Bool {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmationTrimmed = confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNumeric = trimmed.allSatisfy { $0.isNumber }
        return trimmed.count >= 4 && trimmed.count <= 10 && isNumeric && trimmed == confirmationTrimmed
    }

    private func attemptSave() {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmationTrimmed = confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmed.allSatisfy({ $0.isNumber }) else {
            errorMessage = "Passcode must contain only numbers (0-9)."
            return
        }
        guard trimmed.count >= 4 && trimmed.count <= 10 else {
            errorMessage = "Passcode must be 4-10 digits."
            return
        }
        guard trimmed == confirmationTrimmed else {
            errorMessage = "Passcodes do not match."
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
    let allowPasscode: Bool
    let errorMessage: String?
    let isBiometricInFlight: Bool
    let onCancel: () -> Void
    let onBiometric: () -> Void
    let onPasscode: (String) -> Void

    @State private var passcode: String = ""
    @FocusState private var isPasscodeFocused: Bool

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

                if allowPasscode {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("Passcode", text: $passcode)
                            .focused($isPasscodeFocused)
                            .textContentType(.password)
                            .keyboardType(.numberPad)
                            .submitLabel(.done)
                            .onSubmit(submitPasscode)

                        Button("Confirm with Passcode", action: submitPasscode)
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
            if allowPasscode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isPasscodeFocused = true
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

    private func submitPasscode() {
        guard passcode.isEmpty == false else { return }
        onPasscode(passcode)
    }
}

extension SettingsView {
    @ViewBuilder
    private var securityOverlay: some View {
        if let modal = activePasscodeModal {
            PasscodeModalView(
                mode: modal,
                onComplete: handlePasscodeSet(_:),
                onCancel: handlePasscodeCancel
            )
        } else if showReauthModal, let action = pendingSensitiveAction {
            ReauthenticationModalView(
                action: action,
                biometricCapability: biometricCapability,
                allowBiometric: reauthMode.requiresBiometrics && biometricCapability != .none,
                allowPasscode: hasPassphrase,
                errorMessage: reauthErrorMessage,
                isBiometricInFlight: isReauthBiometricInFlight,
                onCancel: cancelReauthentication,
                onBiometric: performBiometricReauthentication,
                onPasscode: validateReauthPasscode(_:)
            )
        }
    }

    private func applyAuthenticationMode(biometric: Bool, passcode: Bool) {
        let newMode: AuthenticationSettings.Mode
        switch (biometric, passcode) {
        case (true, true): newMode = .both
        case (true, false): newMode = .biometricOnly
        case (false, true): newMode = .passphraseOnly
        default: newMode = .disabled
        }
        authStore.update { $0.mode = newMode }
    }

    private func handlePasscodeSet(_ passcode: String) {
        do {
            try passcodeManager.setPassphrase(passcode)
            hasPassphrase = true
            if pendingPasscodeIntent == .enable {
                requirePasscode = true
                applyAuthenticationMode(biometric: requireBiometric, passcode: true)
            }
            pendingPasscodeIntent = nil
            activePasscodeModal = nil
        } catch {
            passcodeErrorMessage = "Unable to store passcode securely."
        }
    }

    private func handlePasscodeCancel() {
        pendingPasscodeIntent = nil
        activePasscodeModal = nil
    }

    private func eraseAll() async {
        await AppDataReset.eraseAll()
    }
    
    private func performCompleteErase() {
        isErasing = true
        Task {
            // Purge server data
            await eraseAll()
            
            // Clear chat state
            await MainActor.run {
                chat.eraseLocalState()
            }
            
            // Remove passcode and biometric
            PassphraseManager.shared.clear()
            await MainActor.run {
                AuthenticationSettingsStore.shared.reset()
            }
            
            // Reset onboarding
            OnboardingManager.shared.resetOnboarding()
            
            // Exit app
            await MainActor.run {
                exit(0)
            }
        }
    }
    
    private func checkServer(_ host: String) async {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            await MainActor.run { serverCheckStatus = .invalid }
            return
        }
        
        guard trimmed.contains(".") || trimmed.contains(":") else {
            await MainActor.run { serverCheckStatus = .invalid }
            return
        }
        
        await MainActor.run { serverCheckStatus = .checking }
        
        guard let url = URL(string: "https://\(trimmed)/") else {
            await MainActor.run { serverCheckStatus = .invalid }
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    await MainActor.run { serverCheckStatus = .online }
                } else {
                    await MainActor.run { serverCheckStatus = .offline }
                }
            } else {
                await MainActor.run { serverCheckStatus = .offline }
            }
        } catch {
            await MainActor.run { serverCheckStatus = .offline }
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

// MARK: - Server Change View
struct ServerChangeView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var editServerHost: String
    @Binding var serverCheckStatus: SettingsView.ServerCheckStatus
    @Binding var serverCheckTask: Task<Void, Never>?
    let onSave: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("server.example.com", text: $editServerHost)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: editServerHost) { oldValue, newValue in
                            serverCheckTask?.cancel()
                            
                            serverCheckTask = Task {
                                try? await Task.sleep(for: .seconds(1))
                                if !Task.isCancelled {
                                    await checkServer(newValue)
                                }
                            }
                        }
                } header: {
                    Text("Server Host")
                } footer: {
                    if serverCheckStatus != .idle {
                        HStack(spacing: 6) {
                            Image(systemName: serverCheckStatus.icon)
                            Text(serverCheckStatus.text)
                        }
                        .foregroundColor(serverCheckStatus.color)
                        .font(.caption)
                    }
                }
                
                Section {
                    Button {
                        Task {
                            await checkServer(editServerHost)
                        }
                    } label: {
                        HStack {
                            Image(systemName: serverCheckStatus.icon)
                                .foregroundColor(serverCheckStatus.color)
                            Text("Check Server")
                            if serverCheckStatus == .checking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(serverCheckStatus == .checking)
                }
            }
            .navigationTitle("Change Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                }
            }
            .onAppear {
                Task {
                    await checkServer(editServerHost)
                }
            }
        }
    }
    
    private func checkServer(_ host: String) async {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            await MainActor.run { serverCheckStatus = .invalid }
            return
        }
        
        guard trimmed.contains(".") || trimmed.contains(":") else {
            await MainActor.run { serverCheckStatus = .invalid }
            return
        }
        
        await MainActor.run { serverCheckStatus = .checking }
        
        guard let url = URL(string: "https://\(trimmed)/") else {
            await MainActor.run { serverCheckStatus = .invalid }
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    await MainActor.run { serverCheckStatus = .online }
                } else {
                    await MainActor.run { serverCheckStatus = .offline }
                }
            } else {
                await MainActor.run { serverCheckStatus = .offline }
            }
        } catch {
            await MainActor.run { serverCheckStatus = .offline }
        }
    }
}
