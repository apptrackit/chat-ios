import SwiftUI

struct PasscodeSetupView: View {
    enum Mode {
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

    let mode: Mode
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var passcode = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case passcode
        case confirmation
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Passcode"), footer: footerView) {
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
        .onAppear { focusedField = .passcode }
    }

    @ViewBuilder
    private var footerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mode.instruction)
            Text("Use only numbers (0-9).")
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            }
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }

    private var isValid: Bool {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let match = trimmed == confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNumeric = trimmed.allSatisfy { $0.isNumber }
        return trimmed.count >= 4 && trimmed.count <= 10 && isNumeric && match
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
        dismiss()
    }
}

#Preview {
    PasscodeSetupView(mode: .create, onComplete: { _ in }, onCancel: {})
}
