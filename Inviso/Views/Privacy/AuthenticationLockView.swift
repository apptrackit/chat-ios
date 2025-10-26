import SwiftUI

struct AuthenticationLockView: View {
    @ObservedObject var manager: AppSecurityManager
    @State private var passcode = ""
    @State private var showEraseConfirm = false
    @State private var eraseConfirmText = ""
    @State private var isErasing = false
    @FocusState private var isPasscodeFocused: Bool

    private var biometricLabel: String {
        switch manager.biometricCapability {
        case .faceID:
            return "Use Face ID"
        case .touchID:
            return "Use Touch ID"
        case .none:
            return "Unlock"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // App icon or lock icon
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                Text("Secure Session Locked")
                    .font(.title2.weight(.semibold))
                
                Text("Enter your passcode to continue")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
                
                // Face ID button if available
                if manager.shouldPromptBiometric && !manager.isAttemptingBiometric {
                    Button {
                        manager.triggerBiometricIfNeeded()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: manager.biometricCapability.systemImageName)
                            Text(biometricLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                
                // Biometric progress
                if manager.isAttemptingBiometric {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Authenticating...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(12)
                }

                // Passcode input - clean and minimal
                if manager.requiresPassphraseEntry && (!manager.shouldPromptBiometric || !manager.isAttemptingBiometric) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Passcode")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SecureField("Enter passcode", text: $passcode)
                            .keyboardType(.numberPad)
                            .focused($isPasscodeFocused)
                            .textContentType(.password)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)

                        if let error = manager.passphraseError {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(error)
                            }
                            .foregroundColor(.red)
                            .font(.caption)
                        }
                        
                        Button {
                            submitPasscode()
                        } label: {
                            Text("Unlock")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(passcode.isEmpty)
                        
                        // Erase all data button
                        Button(role: .destructive) {
                            showEraseConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Erase All Data")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(radius: 20)
            .padding(.horizontal, 24)
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
            if manager.requiresPassphraseEntry && !manager.shouldPromptBiometric {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isPasscodeFocused = true
                }
            }
        }
        .onChange(of: manager.requiresPassphraseEntry) { _, requires in
            if requires && !manager.shouldPromptBiometric {
                passcode = ""
                isPasscodeFocused = true
            }
        }
        .onChange(of: manager.isAttemptingBiometric) { _, attempting in
            if !attempting && manager.requiresPassphraseEntry {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isPasscodeFocused = true
                }
            }
        }
    }

    private func submitPasscode() {
        guard passcode.isEmpty == false else { return }
        manager.submitPassphrase(passcode)
        passcode.removeAll()
    }
    
    private func performCompleteErase() {
        isErasing = true
        Task {
            // Purge server data
            await AppDataReset.eraseAll()
            
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
}

#Preview {
    AuthenticationLockView(manager: AppSecurityManager())
}
