import SwiftUI

struct AuthenticationLockView: View {
    @ObservedObject var manager: AppSecurityManager
    @State private var passphrase = ""
    @FocusState private var isPassphraseFocused: Bool

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

                if manager.shouldPromptBiometric {
                    Button {
                        manager.triggerBiometricIfNeeded()
                    } label: {
                        HStack {
                            Image(systemName: manager.biometricCapability.systemImageName)
                            Text(biometricLabel)
                            if manager.isAttemptingBiometric {
                                Spacer(minLength: 12)
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isAttemptingBiometric)
                }

                if manager.requiresPassphraseEntry {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("Passphrase", text: $passphrase)
                            .focused($isPassphraseFocused)
                            .textContentType(.password)
                            .submitLabel(.done)
                            .onSubmit(submitPassphrase)

                        Button("Unlock with Passphrase", action: submitPassphrase)
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
                    Text("Both biometric verification and the passphrase are required.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else if manager.requiresPassphraseEntry {
                    Text("Enter your passphrase to unlock the app.")
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if manager.requiresPassphraseEntry {
                    isPassphraseFocused = true
                }
            }
        }
        .onChange(of: manager.requiresPassphraseEntry) { requires in
            if requires {
                passphrase = ""
                isPassphraseFocused = true
            }
        }
    }

    private func submitPassphrase() {
        guard passphrase.isEmpty == false else { return }
        manager.submitPassphrase(passphrase)
        passphrase.removeAll()
    }
}

#Preview {
    AuthenticationLockView(manager: AppSecurityManager())
}
