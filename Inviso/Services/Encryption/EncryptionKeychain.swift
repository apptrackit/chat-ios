//
//  EncryptionKeychain.swift
//  Inviso
//
//  Secure Keychain wrapper for encryption keys
//  Created by GitHub Copilot on 10/8/25.
//

import Foundation
import Security

/// Thread-safe Keychain wrapper for storing encryption keys
final class EncryptionKeychain {
    static let shared = EncryptionKeychain()
    
    private let service = "com.inviso.encryption"
    private let queue = DispatchQueue(label: "com.inviso.encryption.keychain", qos: .userInitiated)
    
    init() {}  // Public initializer for ChatManager
    
    // MARK: - Public API
    
    /// Store a cryptographic key in Keychain
    /// - Parameters:
    ///   - key: Key data to store
    ///   - keyType: Type of key (privateKey or sessionKey)
    ///   - sessionId: Session identifier
    /// - Throws: EncryptionError if storage fails
    func setKey(_ key: Data, for keyType: KeyType, sessionId: UUID) throws {
        try queue.sync {
            let account = accountName(for: keyType, sessionId: sessionId)
            
            // Configure access control (hardware encryption, no iCloud sync)
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                [],  // No biometric requirement for background operation
                nil
            ) else {
                throw EncryptionError.keychainUnknownError
            }
            
            let attributes: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: key,
                kSecAttrAccessControl as String: access,
                kSecAttrSynchronizable as String: false,  // NEVER sync to iCloud
                kSecUseDataProtectionKeychain as String: true  // Hardware encryption
            ]
            
            // Try to add, if exists then update
            var status = SecItemAdd(attributes as CFDictionary, nil)
            
            if status == errSecDuplicateItem {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account
                ]
                
                let updateAttributes: [String: Any] = [
                    kSecValueData as String: key
                ]
                
                status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
            }
            
            guard status == errSecSuccess else {
                print("[EncryptionKeychain] Failed to store key: \(status)")
                throw EncryptionError.keychainStoreFailed(status)
            }
            
            print("[EncryptionKeychain] Stored \(keyType.rawValue) for session \(sessionId.uuidString.prefix(8))")
        }
    }
    
    /// Retrieve a cryptographic key from Keychain
    /// - Parameters:
    ///   - keyType: Type of key to retrieve
    ///   - sessionId: Session identifier
    /// - Returns: Key data or nil if not found
    /// - Throws: EncryptionError if retrieval fails
    func getKey(for keyType: KeyType, sessionId: UUID) throws -> Data? {
        try queue.sync {
            let account = accountName(for: keyType, sessionId: sessionId)
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            
            if status == errSecItemNotFound {
                return nil
            }
            
            guard status == errSecSuccess, let data = item as? Data else {
                print("[EncryptionKeychain] Failed to retrieve key: \(status)")
                throw EncryptionError.keychainRetrieveFailed(status)
            }
            
            return data
        }
    }
    
    /// Delete all keys for a specific session
    /// - Parameter sessionId: Session identifier
    /// - Throws: EncryptionError if deletion fails
    func deleteKeys(for sessionId: UUID) throws {
        try queue.sync {
            // Delete private key
            try deleteKey(for: .privateKey, sessionId: sessionId)
            
            // Delete session key
            try deleteKey(for: .sessionKey, sessionId: sessionId)
            
            print("[EncryptionKeychain] Deleted all keys for session \(sessionId.uuidString.prefix(8))")
        }
    }
    
    /// Delete all encryption keys (use with caution!)
    func deleteAllKeys() throws {
        try queue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service
            ]
            
            let status = SecItemDelete(query as CFDictionary)
            
            guard status == errSecSuccess || status == errSecItemNotFound else {
                print("[EncryptionKeychain] Failed to delete all keys: \(status)")
                throw EncryptionError.keychainDeleteFailed(status)
            }
            
            print("[EncryptionKeychain] Deleted all encryption keys")
        }
    }
    
    // MARK: - Private Helpers
    
    private func accountName(for keyType: KeyType, sessionId: UUID) -> String {
        "session.\(sessionId.uuidString).\(keyType.rawValue)"
    }
    
    private func deleteKey(for keyType: KeyType, sessionId: UUID) throws {
        let account = accountName(for: keyType, sessionId: sessionId)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // Success or item not found are both OK
        guard status == errSecSuccess || status == errSecItemNotFound else {
            print("[EncryptionKeychain] Failed to delete \(keyType.rawValue): \(status)")
            throw EncryptionError.keychainDeleteFailed(status)
        }
    }
}

// MARK: - Memory Zeroing Extension

extension Data {
    /// Securely zero out data in memory
    mutating func secureZero() {
        withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            memset_s(baseAddress, ptr.count, 0, ptr.count)
        }
    }
}
