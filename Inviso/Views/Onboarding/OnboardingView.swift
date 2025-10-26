//
//  OnboardingView.swift
//  Inviso
//
//  Main onboarding flow for first-time users.
//

import SwiftUI

extension Color {
    static let onboardingAccent = Color(red: 0x1a / 255.0, green: 0x73 / 255.0, blue: 0x99 / 255.0)
}

struct OnboardingView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var onboardingManager = OnboardingManager.shared
    @ObservedObject private var serverConfig = ServerConfig.shared
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var passcodeError: String?
    @State private var passcodeStep: PasscodeStep = .enter
    @State private var serverHost = ServerConfig.shared.host
    @State private var enableBiometric = false
    @State private var isRequestingPermission = false
    @State private var serverCheckStatus: ServerCheckStatus = .idle
    @State private var serverCheckTask: Task<Void, Never>?
    @State private var permissionsCompleted = false
    
    enum PasscodeStep {
        case enter
        case confirm
    }
    
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
            case .checking: return .onboardingAccent
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
            case .offline: return "Server offline (can still proceed)"
            case .invalid: return "Invalid address"
            }
        }
    }
    
    @FocusState private var passcodeFieldFocused: Bool
    @FocusState private var confirmFieldFocused: Bool
    @FocusState private var serverFieldFocused: Bool
    
    private let biometricCapability = BiometricAuth.shared.capability()
    
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case permissions = 1
        case serverConfig = 2
        case passphrase = 3
        case biometric = 4
        case tutorial = 5
        
        var title: String {
            switch self {
            case .welcome: return "Welcome to Inviso"
            case .permissions: return "Permissions"
            case .serverConfig: return "Server Configuration"
            case .passphrase: return "Set Passphrase"
            case .biometric: return "Biometric Authentication"
            case .tutorial: return "How It Works"
            }
        }
        
        var canSkip: Bool {
            switch self {
            case .biometric, .tutorial: return true
            default: return false
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(white: 0.05), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress indicator
                if currentStep != .welcome {
                    progressBar
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        stepContent
                            .padding(.horizontal, 24)
                            .padding(.top, currentStep == .welcome ? 60 : 20)
                            .padding(.bottom, 120)
                    }
                }
                
                Spacer()
            }
            
            // Navigation buttons
            VStack {
                Spacer()
                navigationButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .background(
                        LinearGradient(
                            colors: [Color.clear, Color(UIColor.systemBackground)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 120)
                        .offset(y: 60)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 6)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.onboardingAccent)
                    .frame(width: geometry.size.width * progress, height: 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
            }
        }
        .frame(height: 6)
    }
    
    private var progress: CGFloat {
        CGFloat(currentStep.rawValue) / CGFloat(OnboardingStep.allCases.count - 1)
    }
    
    // MARK: - Step Content
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .welcome:
            welcomeView
        case .permissions:
            permissionsView
        case .serverConfig:
            serverConfigView
        case .passphrase:
            passphraseView
        case .biometric:
            biometricView
        case .tutorial:
            tutorialView
        }
    }
    
    // MARK: - Welcome
    
    private var welcomeView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // App Icon/Logo
            ZStack {
                // Background circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.onboardingAccent, Color.onboardingAccent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.onboardingAccent.opacity(0.4), radius: 20, y: 10)
                
                // Lock icon
                Image(systemName: "lock.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 16)
            
            Text("Welcome to Inviso")
                .font(.system(size: 36, weight: .bold))
                .multilineTextAlignment(.center)
            
            Text("Private, Secure, Ephemeral Chat")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "lock.fill", text: "End-to-end encrypted messaging")
                FeatureRow(icon: "eye.slash.fill", text: "No data stored on servers")
                FeatureRow(icon: "network", text: "Direct peer-to-peer connections")
                FeatureRow(icon: "timer", text: "Ephemeral sessions, no history")
            }
            .padding(.top, 24)
            
            Spacer()
        }
    }
    
    // MARK: - Permissions
    
    private var permissionsView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.onboardingAccent)
                
                Text("Permissions")
                    .font(.largeTitle.weight(.bold))
            }
            .padding(.bottom, 8)
            
            SequentialPermissionFlow(
                permissionManager: permissionManager,
                isRequestingPermission: $isRequestingPermission,
                allPermissionsCompleted: $permissionsCompleted
            )
            
            Text("You can always change these later in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
    }
    
    // MARK: - Server Config
    
    private var serverConfigView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 64))
                    .foregroundColor(.onboardingAccent)
                
                Text("Server Configuration")
                    .font(.largeTitle.weight(.bold))
                
                Text("Configure the signaling server for peer discovery. You can use the default or specify your own.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 8)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Server Address")
                        .font(.headline)
                    
                    Spacer()
                    
                    // Server check button and status
                    Button {
                        Task {
                            await checkServer(serverHost)
                        }
                    } label: {
                        Image(systemName: serverCheckStatus.icon)
                            .foregroundColor(serverCheckStatus.color)
                            .font(.title3)
                    }
                }
                
                TextField("server.example.com", text: $serverHost)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($serverFieldFocused)
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .onChange(of: serverHost) { oldValue, newValue in
                        // Cancel previous check task
                        serverCheckTask?.cancel()
                        
                        // Debounce server check
                        serverCheckTask = Task {
                            try? await Task.sleep(for: .seconds(1))
                            if !Task.isCancelled {
                                await checkServer(newValue)
                            }
                        }
                    }
                
                // Status text
                if serverCheckStatus != .idle {
                    HStack(spacing: 6) {
                        Image(systemName: serverCheckStatus.icon)
                        Text(serverCheckStatus.text)
                            .font(.caption)
                    }
                    .foregroundColor(serverCheckStatus.color)
                }
                
                Button {
                    serverConfig.resetToDefault()
                    serverHost = serverConfig.host
                } label: {
                    Text("Use Default")
                        .font(.subheadline)
                        .foregroundColor(.onboardingAccent)
                }
            }
            .padding(.horizontal, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("About Servers")
                        .font(.headline)
                }
                
                Text("The server is only used for initial peer discovery. All messages are end-to-end encrypted and sent directly between devices.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
        .onAppear {
            // Auto-check server when user reaches this step
            Task {
                await checkServer(serverHost)
            }
        }
    }
    
    // MARK: - Passcode
    
    private var passphraseView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.onboardingAccent)
                
                Text(passcodeStep == .enter ? "Set Passcode" : "Confirm Passcode")
                    .font(.largeTitle.weight(.bold))
                
                Text(passcodeStep == .enter 
                     ? "Create a numeric passcode to protect your app"
                     : "Re-enter your passcode to confirm")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 16) {
                // Single field that switches between enter and confirm
                if passcodeStep == .enter {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Passcode")
                            .font(.headline)
                        
                        SecureField("Enter passcode (4-10 digits)", text: $passcode)
                            .keyboardType(.numberPad)
                            .textContentType(.newPassword)
                            .focused($passcodeFieldFocused)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                            .onChange(of: passcode) { _, newValue in
                                // Limit to 10 digits and numbers only
                                let filtered = newValue.filter { $0.isNumber }
                                if filtered.count > 10 {
                                    passcode = String(filtered.prefix(10))
                                } else if filtered != newValue {
                                    passcode = filtered
                                }
                                passcodeError = nil
                            }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Passcode")
                            .font(.headline)
                        
                        SecureField("Re-enter passcode", text: $confirmPasscode)
                            .keyboardType(.numberPad)
                            .textContentType(.newPassword)
                            .focused($confirmFieldFocused)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                            .onChange(of: confirmPasscode) { _, newValue in
                                // Limit to 10 digits and numbers only
                                let filtered = newValue.filter { $0.isNumber }
                                if filtered.count > 10 {
                                    confirmPasscode = String(filtered.prefix(10))
                                } else if filtered != newValue {
                                    confirmPasscode = filtered
                                }
                                passcodeError = nil
                            }
                    }
                }
                
                if let error = passcodeError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Passcode Requirements")
                        .font(.headline)
                }
                
                Text("• 4 to 10 digits only\n• Cannot be recovered if forgotten\n• Required to unlock the app")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
        .onAppear {
            passcodeStep = .enter
            passcodeError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                passcodeFieldFocused = true
            }
        }
    }
    
    // MARK: - Biometric
    
    private var biometricView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: biometricCapability.systemImageName)
                    .font(.system(size: 64))
                    .foregroundColor(.onboardingAccent)
                
                Text(biometricCapability == .none ? "Biometric Not Available" : "Enable \(biometricCapability.localizedName)?")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                
                if biometricCapability == .none {
                    Text("Biometric authentication is not available on this device. You'll use your passcode to unlock the app.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Use \(biometricCapability.localizedName) for quick and secure access to your app.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.bottom, 8)
            
            if biometricCapability != .none {
                VStack(spacing: 16) {
                    Toggle(isOn: $enableBiometric) {
                        HStack {
                            Image(systemName: biometricCapability.systemImageName)
                                .font(.title2)
                                .foregroundColor(.onboardingAccent)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable \(biometricCapability.localizedName)")
                                    .font(.headline)
                                Text("Unlock with your face or fingerprint")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(.onboardingAccent)
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .onChange(of: enableBiometric) { _, newValue in
                        if newValue {
                            // Immediately prompt for biometric authentication when toggled on
                            Task {
                                let result = await BiometricAuth.shared.authenticateWithBiometrics(reason: "Confirm your identity to enable \(biometricCapability.localizedName)")
                                if case .success = result {
                                    // Keep enabled
                                    enableBiometric = true
                                } else {
                                    // User cancelled or failed - turn it back off
                                    enableBiometric = false
                                }
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.onboardingAccent)
                            Text("Note")
                                .font(.headline)
                        }
                        
                        Text("You can still use your passcode to unlock even with \(biometricCapability.localizedName) enabled.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(Color.onboardingAccent.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    // MARK: - Tutorial
    
    private var tutorialView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.onboardingAccent)
                
                Text("How It Works")
                    .font(.largeTitle.weight(.bold))
                
                Text("Here's everything you need to know to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 20) {
                TutorialStep(
                    number: 1,
                    icon: "person.2.fill",
                    title: "Create or Join a Room",
                    description: "Start a new session or join an existing one using a room code."
                )
                
                TutorialStep(
                    number: 2,
                    icon: "lock.shield.fill",
                    title: "Encrypted Connection",
                    description: "All messages are end-to-end encrypted. Only you and your peer can read them."
                )
                
                TutorialStep(
                    number: 3,
                    icon: "message.fill",
                    title: "Send Messages",
                    description: "Send text, voice messages, and location. No history is saved."
                )
                
                TutorialStep(
                    number: 4,
                    icon: "timer",
                    title: "Sessions Expire",
                    description: "All sessions automatically expire after 24 hours for maximum privacy."
                )
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Privacy First")
                        .font(.headline)
                }
                
                Text("No message history, no tracking, no analytics. Your privacy is our priority.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep.rawValue > 0 {
                Button {
                    withAnimation {
                        goToPreviousStep()
                    }
                } label: {
                    Text("Back")
                        .font(.headline)
                        .foregroundColor(.onboardingAccent)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                }
            }
            
            Button {
                handleNextButton()
            } label: {
                HStack {
                    Text(nextButtonTitle)
                        .font(.headline)
                    if currentStep == .tutorial {
                        Image(systemName: "checkmark")
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.onboardingAccent)
                .cornerRadius(12)
            }
            .disabled(!canProceed)
            .opacity(canProceed ? 1.0 : 0.5)
        }
    }
    
    private var nextButtonTitle: String {
        if currentStep == .tutorial {
            return "Get Started"
        } else if currentStep == .passphrase {
            return passcodeStep == .enter ? "Next" : "Done"
        } else if currentStep.canSkip {
            return "Continue"
        } else {
            return "Next"
        }
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case .welcome, .serverConfig, .tutorial, .biometric:
            return true
        case .permissions:
            return permissionsCompleted
        case .passphrase:
            if passcodeStep == .enter {
                return passcode.count >= 4 && passcode.count <= 10 && passcode.allSatisfy({ $0.isNumber })
            } else {
                return isPassphraseValid
            }
        }
    }
    
    private var isPassphraseValid: Bool {
        !passcode.isEmpty && passcode.count >= 4 && passcode.count <= 10 && passcode == confirmPasscode
    }
    
    // MARK: - Navigation Logic
    
    private func handleNextButton() {
        // Special handling for passcode step
        if currentStep == .passphrase {
            if passcodeStep == .enter {
                // Move from enter to confirm
                passcodeFieldFocused = false
                passcodeStep = .confirm
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    confirmFieldFocused = true
                }
                return
            } else {
                // Validate and save
                if !validatePassphrase() {
                    return
                }
                savePassphrase()
            }
        }
        
        // Validate other steps
        switch currentStep {
        case .serverConfig:
            saveServerConfig()
        case .biometric:
            saveBiometricPreference()
        default:
            break
        }
        
        // Navigate
        if currentStep == .tutorial {
            completeOnboarding()
        } else {
            withAnimation {
                goToNextStep()
            }
        }
    }
    
    private func goToNextStep() {
        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            currentStep = nextStep
        }
    }
    
    private func goToPreviousStep() {
        // Special handling for passcode step
        if currentStep == .passphrase && passcodeStep == .confirm {
            // Go back to enter step
            confirmFieldFocused = false
            passcodeStep = .enter
            confirmPasscode = ""
            passcodeError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                passcodeFieldFocused = true
            }
            return
        }
        
        // Normal previous step
        if let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            currentStep = prevStep
        }
    }
    
    // MARK: - Data Saving
    
    private func checkServer(_ host: String) async {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic validation
        guard !trimmed.isEmpty else {
            await MainActor.run { serverCheckStatus = .invalid }
            return
        }
        
        // Check if it looks like a valid host
        guard trimmed.contains(".") || trimmed.contains(":") else {
            await MainActor.run { serverCheckStatus = .invalid }
            return
        }
        
        await MainActor.run { serverCheckStatus = .checking }
        
        // Try to reach the server
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
            // Server might be offline but address could be valid
            await MainActor.run { serverCheckStatus = .offline }
        }
    }
    
    private func validatePassphrase() -> Bool {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmedTrimmed = confirmPasscode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmed.count >= 4 else {
            passcodeError = "Passcode must be at least 4 digits"
            return false
        }
        
        guard trimmed.count <= 10 else {
            passcodeError = "Passcode cannot exceed 10 digits"
            return false
        }
        
        guard trimmed.allSatisfy({ $0.isNumber }) else {
            passcodeError = "Passcode must contain only numbers"
            return false
        }
        
        guard trimmed == confirmedTrimmed else {
            passcodeError = "Passcodes do not match"
            return false
        }
        
        return true
    }
    
    private func savePassphrase() {
        do {
            try PassphraseManager.shared.setPassphrase(passcode)
        } catch {
            passcodeError = "Failed to save passcode. Please try again."
        }
    }
    
    private func saveServerConfig() {
        let sanitized = ServerConfig.sanitize(serverHost)
        if !sanitized.isEmpty {
            serverConfig.updateHost(sanitized)
        }
    }
    
    private func saveBiometricPreference() {
        if enableBiometric && biometricCapability != .none {
            // Enable biometric with passphrase
            AuthenticationSettingsStore.shared.update { settings in
                settings.mode = .both
            }
        } else {
            // Passphrase only
            AuthenticationSettingsStore.shared.update { settings in
                settings.mode = .passphraseOnly
            }
        }
    }
    
    private func completeOnboarding() {
        onboardingManager.completeOnboarding()
    }
}

// MARK: - Supporting Views

private struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.onboardingAccent)
                .frame(width: 32)
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Sequential Permission Flow

private struct SequentialPermissionFlow: View {
    @ObservedObject var permissionManager: PermissionManager
    @Binding var isRequestingPermission: Bool
    @Binding var allPermissionsCompleted: Bool
    @State private var currentPermissionIndex = 0
    @State private var showingLocalNetworkInfo = false
    
    private let permissions: [(icon: String, title: String, description: String, keyPath: KeyPath<PermissionManager, PermissionManager.PermissionStatus>, request: (PermissionManager) async -> Bool)] = [
        (icon: "location.fill", title: "Location", description: "Share your location in chats", keyPath: \.locationStatus, request: { await $0.requestLocationPermission() }),
        (icon: "mic.fill", title: "Microphone", description: "Record and send voice messages", keyPath: \.microphoneStatus, request: { await $0.requestMicrophonePermission() }),
        (icon: "camera.fill", title: "Camera", description: "Scan QR codes to join rooms quickly", keyPath: \.cameraStatus, request: { await $0.requestCameraPermission() }),
        (icon: "bell.fill", title: "Notifications", description: "Get notified when someone joins", keyPath: \.notificationStatus, request: { await $0.requestNotificationPermission() })
    ]
    
    private var currentPermission: (icon: String, title: String, description: String, keyPath: KeyPath<PermissionManager, PermissionManager.PermissionStatus>, request: (PermissionManager) async -> Bool)? {
        guard currentPermissionIndex < permissions.count else { return nil }
        return permissions[currentPermissionIndex]
    }
    
    private var currentStatus: PermissionManager.PermissionStatus {
        guard let perm = currentPermission else { return .authorized }
        return permissionManager[keyPath: perm.keyPath]
    }
    
    var body: some View {
        VStack(spacing: 20) {
            if let perm = currentPermission {
                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(0..<permissions.count, id: \.self) { index in
                        Circle()
                            .fill(index < currentPermissionIndex ? Color.green : (index == currentPermissionIndex ? Color.onboardingAccent : Color.gray.opacity(0.3)))
                            .frame(width: 8, height: 8)
                    }
                    
                    // Extra dot for local network info
                    Circle()
                        .fill(showingLocalNetworkInfo ? Color.onboardingAccent : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
                .padding(.bottom, 8)
                
                // Current permission card
                VStack(spacing: 20) {
                    Image(systemName: perm.icon)
                        .font(.system(size: 64))
                        .foregroundColor(.onboardingAccent)
                    
                    VStack(spacing: 8) {
                        Text(perm.title)
                            .font(.title2.weight(.bold))
                        
                        Text(perm.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Status badge
                    HStack(spacing: 6) {
                        Image(systemName: statusIcon(currentStatus))
                        Text(currentStatus.displayText)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(statusColor(currentStatus))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(statusColor(currentStatus).opacity(0.15))
                    .cornerRadius(20)
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        if currentStatus == .notDetermined {
                            Button {
                                isRequestingPermission = true
                                Task {
                                    _ = await perm.request(permissionManager)
                                    isRequestingPermission = false
                                    // Auto-advance after granting/denying
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        withAnimation {
                                            advanceToNext()
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    if isRequestingPermission {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                        Text("Enable")
                                            .font(.headline)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.onboardingAccent)
                                )
                                .foregroundColor(.white)
                                .shadow(color: Color.onboardingAccent.opacity(0.3), radius: 8, y: 4)
                            }
                            .disabled(isRequestingPermission)
                            
                            Button {
                                withAnimation {
                                    advanceToNext()
                                }
                            } label: {
                                Text("Skip for Now")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            }
                        } else if currentStatus == .denied {
                            Button {
                                permissionManager.openSettings()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "gear")
                                        .font(.title3)
                                    Text("Open Settings")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.orange)
                                )
                                .foregroundColor(.white)
                                .shadow(color: Color.orange.opacity(0.3), radius: 8, y: 4)
                            }
                            
                            Button {
                                withAnimation {
                                    advanceToNext()
                                }
                            } label: {
                                Text("Continue Anyway")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            }
                        } else {
                            Button {
                                withAnimation {
                                    advanceToNext()
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Text("Continue")
                                        .font(.headline)
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.title3)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.green)
                                )
                                .foregroundColor(.white)
                                .shadow(color: Color.green.opacity(0.3), radius: 8, y: 4)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(16)
            } else {
                // Show local network info before completion
                if !showingLocalNetworkInfo {
                    localNetworkInfoCard
                } else {
                    // All done
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)
                        
                        Text("Permissions Set!")
                            .font(.title2.weight(.bold))
                        
                        Text("You can manage permissions anytime in Settings")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
        }
    }
    
    // Local network info card
    private var localNetworkInfoCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 64))
                .foregroundColor(.onboardingAccent)
            
            VStack(spacing: 8) {
                Text("Local Network Access")
                    .font(.title2.weight(.bold))
                
                Text("When you join a P2P room, iOS will ask for permission to find devices on your local network. This allows direct peer-to-peer connections without using external servers.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Info badge
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                Text("Asked automatically when needed")
                    .font(.caption)
            }
            .foregroundColor(.onboardingAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.onboardingAccent.opacity(0.15))
            .cornerRadius(20)
            
            // Continue button
            Button {
                withAnimation {
                    showingLocalNetworkInfo = true
                    allPermissionsCompleted = true
                }
            } label: {
                HStack {
                    Text("Got It")
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.onboardingAccent)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private func advanceToNext() {
        if currentPermissionIndex < permissions.count {
            currentPermissionIndex += 1
        }
    }
    
    private func statusIcon(_ status: PermissionManager.PermissionStatus) -> String {
        switch status {
        case .notDetermined: return "questionmark.circle"
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .restricted: return "exclamationmark.circle.fill"
        }
    }
    
    private func statusColor(_ status: PermissionManager.PermissionStatus) -> Color {
        switch status {
        case .notDetermined: return .orange
        case .authorized: return .green
        case .denied: return .red
        case .restricted: return .gray
        }
    }
}

// MARK: - Supporting Views

private struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionManager.PermissionStatus
    let isRequesting: Bool
    let onRequest: () -> Void
    let onSettings: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.onboardingAccent)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                statusBadge
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            
            if status == .denied {
                Button {
                    onSettings()
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text("Open Settings")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.onboardingAccent)
                    .padding(.vertical, 8)
                }
            } else if status == .notDetermined {
                Button {
                    onRequest()
                } label: {
                    HStack {
                        if isRequesting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Enable")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .foregroundColor(.onboardingAccent)
                    .padding(.vertical, 8)
                }
                .disabled(isRequesting)
            }
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
            Text(status.displayText)
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(statusColor)
    }
    
    private var statusIcon: String {
        switch status {
        case .notDetermined: return "questionmark.circle"
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .restricted: return "exclamationmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .notDetermined: return .orange
        case .authorized: return .green
        case .denied: return .red
        case .restricted: return .gray
        }
    }
}

private struct TutorialStep: View {
    let number: Int
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.onboardingAccent)
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    OnboardingView()
}
