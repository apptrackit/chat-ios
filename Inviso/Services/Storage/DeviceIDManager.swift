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
