//
//  OnboardingView.swift
//  Inviso
//
//  Main onboarding flow for first-time users.
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var onboardingManager = OnboardingManager.shared
    @ObservedObject private var serverConfig = ServerConfig.shared
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var passphraseError: String?
    @State private var serverHost = ServerConfig.shared.host
    @State private var enableBiometric = false
    @State private var isRequestingPermission = false
    
    @FocusState private var passphraseFieldFocused: Bool
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
                colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.1)],
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
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
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
            
            Image(systemName: "lock.shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
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
                FeatureRow(icon: "eye.slash.fill", text: "No message history stored")
                FeatureRow(icon: "network", text: "Direct peer-to-peer connections")
                FeatureRow(icon: "timer", text: "Messages expire after 24 hours")
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
                    .foregroundColor(.blue)
                
                Text("Permissions")
                    .font(.largeTitle.weight(.bold))
                
                Text("Inviso needs your permission to enable certain features. You can enable or skip any permission.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 16) {
                PermissionCard(
                    icon: "location.fill",
                    title: "Location",
                    description: "Share your location in chats",
                    status: permissionManager.locationStatus,
                    isRequesting: isRequestingPermission,
                    onRequest: {
                        isRequestingPermission = true
                        Task {
                            _ = await permissionManager.requestLocationPermission()
                            isRequestingPermission = false
                        }
                    },
                    onSettings: permissionManager.openSettings
                )
                
                PermissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Send voice messages",
                    status: permissionManager.microphoneStatus,
                    isRequesting: isRequestingPermission,
                    onRequest: {
                        isRequestingPermission = true
                        Task {
                            _ = await permissionManager.requestMicrophonePermission()
                            isRequestingPermission = false
                        }
                    },
                    onSettings: permissionManager.openSettings
                )
                
                PermissionCard(
                    icon: "bell.fill",
                    title: "Notifications",
                    description: "Get notified when someone joins",
                    status: permissionManager.notificationStatus,
                    isRequesting: isRequestingPermission,
                    onRequest: {
                        isRequestingPermission = true
                        Task {
                            _ = await permissionManager.requestNotificationPermission()
                            isRequestingPermission = false
                        }
                    },
                    onSettings: permissionManager.openSettings
                )
            }
            
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
                    .foregroundColor(.blue)
                
                Text("Server Configuration")
                    .font(.largeTitle.weight(.bold))
                
                Text("Enter your signaling server address. Use the default or specify your own.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 8)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Server Address")
                    .font(.headline)
                
                HStack {
                    TextField("Server host", text: $serverHost)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($serverFieldFocused)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                    
                    Button {
                        serverHost = "chat.ballabotond.com"
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.blue)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                    }
                }
                
                Text("Default: chat.ballabotond.com")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("About the Server")
                        .font(.headline)
                }
                
                Text("The server is only used for initial peer discovery. All messages are sent directly between devices using end-to-end encryption.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Passphrase
    
    private var passphraseView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                Text("Set Passphrase")
                    .font(.largeTitle.weight(.bold))
                
                Text("Create a passphrase to protect your app. This is required and cannot be recovered if forgotten.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 8)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Passphrase")
                        .font(.headline)
                    
                    SecureField("Enter passphrase (min 8 characters)", text: $passphrase)
                        .textContentType(.newPassword)
                        .focused($passphraseFieldFocused)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .onChange(of: passphrase) { _, _ in
                            passphraseError = nil
                        }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirm Passphrase")
                        .font(.headline)
                    
                    SecureField("Re-enter passphrase", text: $confirmPassphrase)
                        .textContentType(.newPassword)
                        .focused($confirmFieldFocused)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .onChange(of: confirmPassphrase) { _, _ in
                            passphraseError = nil
                        }
                }
                
                if let error = passphraseError {
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
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Important")
                        .font(.headline)
                }
                
                Text("• Minimum 8 characters\n• Cannot be recovered if forgotten\n• Required to unlock the app")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                passphraseFieldFocused = true
            }
        }
    }
    
    // MARK: - Biometric
    
    private var biometricView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: biometricCapability.systemImageName)
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                Text(biometricCapability == .none ? "Biometric Not Available" : "Enable \(biometricCapability.localizedName)?")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                
                if biometricCapability == .none {
                    Text("Biometric authentication is not available on this device. You'll use your passphrase to unlock the app.")
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
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable \(biometricCapability.localizedName)")
                                    .font(.headline)
                                Text("Unlock with your face or fingerprint")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(.blue)
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Note")
                                .font(.headline)
                        }
                        
                        Text("You can still use your passphrase to unlock even with \(biometricCapability.localizedName) enabled.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
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
                    .foregroundColor(.blue)
                
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
                        .foregroundColor(.blue)
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
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(!canProceed)
            .opacity(canProceed ? 1.0 : 0.5)
        }
    }
    
    private var nextButtonTitle: String {
        if currentStep == .tutorial {
            return "Get Started"
        } else if currentStep.canSkip {
            return "Continue"
        } else {
            return "Next"
        }
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case .welcome, .permissions, .serverConfig, .tutorial, .biometric:
            return true
        case .passphrase:
            return isPassphraseValid
        }
    }
    
    private var isPassphraseValid: Bool {
        !passphrase.isEmpty && passphrase.count >= 8 && passphrase == confirmPassphrase
    }
    
    // MARK: - Navigation Logic
    
    private func handleNextButton() {
        // Validate current step
        switch currentStep {
        case .passphrase:
            if !validatePassphrase() {
                return
            }
            savePassphrase()
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
        if let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            currentStep = prevStep
        }
    }
    
    // MARK: - Data Saving
    
    private func validatePassphrase() -> Bool {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmedTrimmed = confirmPassphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmed.count >= 8 else {
            passphraseError = "Passphrase must be at least 8 characters"
            return false
        }
        
        guard trimmed == confirmedTrimmed else {
            passphraseError = "Passphrases do not match"
            return false
        }
        
        return true
    }
    
    private func savePassphrase() {
        do {
            try PassphraseManager.shared.setPassphrase(passphrase)
        } catch {
            passphraseError = "Failed to save passphrase. Please try again."
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
                .foregroundColor(.blue)
                .frame(width: 32)
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

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
                    .foregroundColor(.blue)
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
                    .foregroundColor(.blue)
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
                    .foregroundColor(.blue)
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
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
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
