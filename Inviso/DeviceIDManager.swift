//
//  DeviceIDManager.swift
//  Inviso
//
//  Provides an app-scoped persistent UUID stored in the Keychain.
//  This ID survives app reinstalls (device/keychain permitting) and
//  resets only if the device is wiped, keychain is cleared, or the
//  app's keychain access group changes.
//

import Foundation
import Security

enum KeychainError: Error {
    case unhandled(status: OSStatus)
}

final class KeychainService {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setString(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Not synced to iCloud; available after first unlock
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let update: [String: Any] = [
                kSecValueData as String: data
            ]
            status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status: status) }
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status: status)
        }
    }
}

final class DeviceIDManager {
    static let shared = DeviceIDManager()

    private let keychain: KeychainService
    private let account = "device-id"
    private var cachedID: String

    private init() {
        // Use bundle identifier for keychain service scoping, with a suffix
        let baseService = Bundle.main.bundleIdentifier ?? "inviso"
        self.keychain = KeychainService(service: baseService + ".deviceid")

        if let existing = keychain.string(for: account) {
            self.cachedID = existing
        } else {
            let newID = UUID().uuidString
            // Best-effort write; if it fails, still return the generated value
            try? keychain.setString(newID, for: account)
            self.cachedID = newID
        }
    }

    /// Stable app-scoped identifier backed by Keychain.
    var id: String { cachedID }

    /// Deletes the current ID from Keychain and generates a new one.
    func reset() {
        try? keychain.delete(account: account)
        let newID = UUID().uuidString
        try? keychain.setString(newID, for: account)
        self.cachedID = newID
    }
}
