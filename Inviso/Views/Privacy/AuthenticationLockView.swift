import SwiftUI

struct AuthenticationLockView: View {
    @ObservedObject var manager: AppSecurityManager
    @State private var passcode = ""
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
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") {
                                        submitPasscode()
                                    }
                                    .disabled(passcode.isEmpty)
                                }
                            }

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
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(radius: 20)
            .padding(.horizontal, 24)
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
}

#Preview {
    AuthenticationLockView(manager: AppSecurityManager())
}
