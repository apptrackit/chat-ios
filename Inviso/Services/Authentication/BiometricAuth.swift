import Foundation
import LocalAuthentication

enum BiometricCapability {
    case none
    case touchID
    case faceID

    init(type: LABiometryType) {
        switch type {
        case .touchID: self = .touchID
        case .faceID: self = .faceID
        default: self = .none
        }
    }

    var localizedName: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .none: return "Biometrics"
        }
    }

    var systemImageName: String {
        switch self {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock"
        }
    }
}

enum BiometricAuthResult {
    case success
    case cancelled
    case fallback
    case failed(LAError.Code)
}

final class BiometricAuth {
    static let shared = BiometricAuth()

    private init() {}

    func capability() -> BiometricCapability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let laError = error as? LAError, laError.code == .biometryLockout {
                // When locked out, still show available biometry type if known
                return BiometricCapability(type: context.biometryType)
            }
            return .none
        }
        return BiometricCapability(type: context.biometryType)
    }

    func canEvaluateBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticate(reason: String, allowDevicePasscode: Bool, fallbackTitle: String? = nil) async -> BiometricAuthResult {
        let context = LAContext()
        context.localizedFallbackTitle = allowDevicePasscode ? fallbackTitle : ""
        let policy: LAPolicy = allowDevicePasscode ? .deviceOwnerAuthentication : .deviceOwnerAuthenticationWithBiometrics

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: .success)
                    return
                }

                if let laError = error as? LAError {
                    switch laError.code {
                    case .userCancel, .appCancel, .systemCancel:
                        continuation.resume(returning: .cancelled)
                    case .userFallback:
                        continuation.resume(returning: .fallback)
                    default:
                        continuation.resume(returning: .failed(laError.code))
                    }
                } else {
                    continuation.resume(returning: .failed(.authenticationFailed))
                }
            }
        }
    }

    func authenticateWithBiometrics(reason: String) async -> BiometricAuthResult {
        await authenticate(reason: reason, allowDevicePasscode: false)
    }

    func authenticateAllowingDevicePasscode(reason: String, fallbackTitle: String? = nil) async -> BiometricAuthResult {
        await authenticate(reason: reason, allowDevicePasscode: true, fallbackTitle: fallbackTitle)
    }
}
