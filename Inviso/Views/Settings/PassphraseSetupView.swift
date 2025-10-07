import SwiftUI

struct PassphraseSetupView: View {
    enum Mode {
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

    let mode: Mode
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case passphrase
        case confirmation
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Passphrase"), footer: footerView) {
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
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .disabled(!isValid)
                }
            }
        }
        .onAppear { focusedField = .passphrase }
    }

    @ViewBuilder
    private var footerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mode.instruction)
            Text("Avoid using easily guessable information.")
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            }
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }

    private var isValid: Bool {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let match = trimmed == confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 8 && match
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
        dismiss()
    }
}

#Preview {
    PassphraseSetupView(mode: .create, onComplete: { _ in }, onCancel: {})
}
