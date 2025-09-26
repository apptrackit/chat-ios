import Foundation
import Combine
import CryptoKit
import Security

struct AuthenticationSettings: Codable, Equatable {
    enum Mode: Int, Codable {
        case disabled = 0
        case biometricOnly
        case passphraseOnly
        case both

        var requiresBiometrics: Bool { self == .biometricOnly || self == .both }
        var requiresPassphrase: Bool { self == .passphraseOnly || self == .both }
    }

    var mode: Mode

    static let `default` = AuthenticationSettings(mode: .disabled)
}

final class AuthenticationSettingsStore: ObservableObject {
    static let shared = AuthenticationSettingsStore()

    @Published private(set) var settings: AuthenticationSettings

    private let storeKey = "auth.settings.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let decoded = try? JSONDecoder().decode(AuthenticationSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    func update(_ transform: (inout AuthenticationSettings) -> Void) {
        var copy = settings
        transform(&copy)
        guard copy != settings else { return }
        settings = copy
        persist()
    }

    func reset() {
        settings = .default
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }
}

private struct PassphraseRecord: Codable {
    let salt: Data
    let hash: Data
}

final class PassphraseManager {
    static let shared = PassphraseManager()

    private let keychain: KeychainService
    private let account = "auth-passphrase"

    private init() {
        let baseService = Bundle.main.bundleIdentifier ?? "inviso"
        self.keychain = KeychainService(service: baseService + ".auth")
    }

    var hasPassphrase: Bool { storedRecord != nil }

    func setPassphrase(_ passphrase: String) throws {
        let salt = randomSalt()
        let hash = PassphraseManager.hash(passphrase: passphrase, salt: salt)
        let record = PassphraseRecord(salt: salt, hash: hash)
        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        try keychain.setData(data, for: account)
    }

    func validate(passphrase: String) -> Bool {
        guard let record = storedRecord else { return false }
        let hash = PassphraseManager.hash(passphrase: passphrase, salt: record.salt)
        return hash == record.hash
    }

    func clear() {
        try? keychain.delete(account: account)
    }

    private var storedRecord: PassphraseRecord? {
        guard let data = keychain.data(for: account) else { return nil }
        return try? JSONDecoder().decode(PassphraseRecord.self, from: data)
    }

    private func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: .min ... .max)
            }
        }
        return Data(bytes)
    }

    private static func hash(passphrase: String, salt: Data) -> Data {
        var hasher = SHA256()
        hasher.update(data: salt)
        hasher.update(data: Data(passphrase.utf8))
        return Data(hasher.finalize())
    }
}

private extension KeychainService {
    func data(for account: String) -> Data? {
        guard let string = string(for: account) else { return nil }
        return Data(base64Encoded: string)
    }

    func setData(_ data: Data, for account: String) throws {
        let string = data.base64EncodedString()
        try setString(string, for: account)
    }
}
