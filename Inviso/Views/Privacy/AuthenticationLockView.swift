import SwiftUI

struct AuthenticationLockView: View {
    @ObservedObject var manager: AppSecurityManager
    @State private var passcode = ""
    @FocusState private var isPasscodeFocused: Bool

    private var biometricLabel: String {
        switch manager.biometricCapability {
        case .faceID:
            return "Unlock with Face ID"
        case .touchID:
            return "Unlock with Touch ID"
        case .none:
            return "Unlock"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(.primary)

                VStack(spacing: 8) {
                    Text("Secure Session Locked")
                        .font(.title3.weight(.semibold))
                    Text("Authenticate to resume your encrypted conversations.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Show Face ID button if available and not attempting
                if manager.shouldPromptBiometric && !manager.isAttemptingBiometric {
                    Button {
                        manager.triggerBiometricIfNeeded()
                    } label: {
                        HStack {
                            Image(systemName: manager.biometricCapability.systemImageName)
                            Text(biometricLabel)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                // Show biometric progress if attempting
                if manager.isAttemptingBiometric {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: manager.biometricCapability.systemImageName)
                            Text("Authenticating...")
                            Spacer(minLength: 12)
                            ProgressView()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(12)
                        
                        Text("Look at your device to unlock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Show passcode field only if:
                // 1. Passcode is required AND
                // 2. (Biometric not available OR biometric already attempted/failed OR explicitly requiring passcode entry)
                if manager.requiresPassphraseEntry && (!manager.shouldPromptBiometric || !manager.isAttemptingBiometric) {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("Passcode", text: $passcode)
                            .keyboardType(.numberPad)
                            .focused($isPasscodeFocused)
                            .textContentType(.password)
                            .submitLabel(.done)
                            .onSubmit(submitPasscode)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)

                        Button("Unlock with Passcode", action: submitPasscode)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let error = manager.passphraseError {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.footnote)
                        }
                    }
                }

                if manager.requiresPassphraseEntry, manager.shouldPromptBiometric {
                    Text("Use \(manager.biometricCapability.localizedName) or enter your passcode to unlock.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else if manager.requiresPassphraseEntry {
                    Text("Enter your passcode to unlock the app.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(radius: 18)
            .padding(.horizontal, 32)
        }
        .onAppear {
            // Don't auto-focus passcode if biometric is available and will be attempted
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
            // When biometric attempt finishes, auto-focus passcode if still needed
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
}

#Preview {
    AuthenticationLockView(manager: AppSecurityManager())
}
