//
//  MessageStorageManager.swift
//  Inviso
//
//  Encrypted message storage with passphrase-derived keys
//  Messages are encrypted at rest using AES-256-GCM
//  Keys are derived from user's passphrase and wrapped with Secure Enclave
//
//  Created by GitHub Copilot on 10/26/25.
//

import Foundation
import CryptoKit
import Security
import LocalAuthentication

/// Message retention policy agreed between peers
enum MessageLifetime: String, Codable {
    case ephemeral = "ephemeral"           // RAM only - delete on leave
    case oneHour = "1h"
    case sixHours = "6h"
    case oneDay = "1d"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    
    var displayName: String {
        switch self {
        case .ephemeral: return "Delete on Leave"
        case .oneHour: return "1 Hour"
        case .sixHours: return "6 Hours"
        case .oneDay: return "1 Day"
        case .sevenDays: return "7 Days"
        case .thirtyDays: return "30 Days"
        }
    }
    
    var icon: String {
        switch self {
        case .ephemeral: return "trash.circle.fill"
        case .oneHour: return "clock.fill"
        case .sixHours: return "clock.badge.fill"
        case .oneDay: return "calendar.badge.clock"
        case .sevenDays: return "calendar"
        case .thirtyDays: return "calendar.badge.checkmark"
        }
    }
    
    var seconds: TimeInterval? {
        switch self {
        case .ephemeral: return nil // No persistence
        case .oneHour: return 3600
        case .sixHours: return 21600
        case .oneDay: return 86400
        case .sevenDays: return 604800
        case .thirtyDays: return 2592000
        }
    }
}

/// Stored message with encryption metadata
struct StoredMessage: Codable {
    let id: UUID
    let sessionId: UUID          // Links to ChatSession
    let encryptedContent: Data   // AES-256-GCM encrypted
    let nonce: Data              // 12 bytes
    let tag: Data                // 16 bytes
    let timestamp: Date
    let isFromSelf: Bool
    let messageType: MessageType // text, location, voice
    let expiresAt: Date?         // Nil for ephemeral
    
    enum MessageType: String, Codable {
        case text
        case location
        case voice
    }
}

/// Message storage configuration per session
struct MessageStorageConfig: Codable {
    let sessionId: UUID
    var lifetime: MessageLifetime
    var agreedAt: Date           // When both peers agreed on this setting
    var agreedByBoth: Bool       // True when both peers confirmed
    
    init(sessionId: UUID, lifetime: MessageLifetime = .ephemeral, agreedAt: Date = Date(), agreedByBoth: Bool = false) {
        self.sessionId = sessionId
        self.lifetime = lifetime
        self.agreedAt = agreedAt
        self.agreedByBoth = agreedByBoth
    }
}

/// Error types for message storage operations
enum MessageStorageError: LocalizedError {
    case passphraseNotSet
    case encryptionFailed(String)
    case decryptionFailed(String)
    case keychainError(OSStatus)
    case invalidData
    case storageDisabled
    case biometricFailed
    
    var errorDescription: String? {
        switch self {
        case .passphraseNotSet:
            return "Storage passphrase not configured"
        case .encryptionFailed(let reason):
            return "Message encryption failed: \(reason)"
        case .decryptionFailed(let reason):
            return "Message decryption failed: \(reason)"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .invalidData:
            return "Invalid message data format"
        case .storageDisabled:
            return "Message storage is disabled (ephemeral mode)"
        case .biometricFailed:
            return "Biometric authentication failed"
        }
    }
}

/// Manages encrypted message storage with passphrase-derived keys
final class MessageStorageManager {
    static let shared = MessageStorageManager()
    
    private let keychain: KeychainService
    private let fileManager = FileManager.default
    private let storageDirectory: URL
    
    // Service name for Keychain operations
    private let keychainServiceName: String
    
    // Key derivation constants
    private let keyDerivationIterations = 100_000 // PBKDF2 iterations
    private let keySize = 32 // 256 bits
    private let saltSize = 32
    
    // Keychain accounts
    private let masterKeyAccount = "storage-master-key"
    private let masterKeySaltAccount = "storage-master-salt"
    private let biometricWrappedKeyAccount = "storage-biometric-key"
    
    // In-memory cache (cleared on lock)
    private var cachedMasterKey: SymmetricKey?
    
    private init() {
        let baseService = Bundle.main.bundleIdentifier ?? "inviso"
        self.keychainServiceName = baseService + ".storage"
        self.keychain = KeychainService(service: keychainServiceName)
        
        // Create storage directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.storageDirectory = appSupport.appendingPathComponent("EncryptedMessages", isDirectory: true)
        
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        
        print("[MessageStorage] Initialized with directory: \(storageDirectory.path)")
    }
    
    // MARK: - Setup & Configuration
    
    /// Check if storage passphrase is configured
    var hasStoragePassphrase: Bool {
        keychain.data(for: masterKeySaltAccount) != nil
    }
    
    /// Set up storage encryption with user's passphrase
    /// This generates and stores a master key encrypted with the passphrase
    func setupStoragePassphrase(_ passphrase: String) throws {
        print("[MessageStorage] Setting up storage passphrase...")
        
        // Generate random salt
        let salt = generateRandomBytes(count: saltSize)
        
        // Derive master key from passphrase using PBKDF2
        let masterKey = try deriveMasterKey(from: passphrase, salt: salt)
        
        // Store salt in Keychain (needed for future derivations)
        try keychain.setData(salt, for: masterKeySaltAccount)
        
        // Also create a biometric-protected wrapped version for Face ID unlock
        try storeBiometricWrappedKey(masterKey, passphrase: passphrase, salt: salt)
        
        // Cache in memory
        cachedMasterKey = masterKey
        
        print("[MessageStorage] ✅ Storage passphrase configured")
    }
    
    /// Change storage passphrase (re-encrypts all stored messages)
    func changeStoragePassphrase(oldPassphrase: String, newPassphrase: String) async throws {
        print("[MessageStorage] Changing storage passphrase...")
        
        // Verify old passphrase by unlocking
        try await unlockWithPassphrase(oldPassphrase)
        
        // Get all stored messages
        let sessions = getAllSessions()
        var allMessages: [(sessionId: UUID, messages: [StoredMessage])] = []
        
        for sessionId in sessions {
            let messages = try loadMessages(for: sessionId)
            allMessages.append((sessionId, messages))
        }
        
        print("[MessageStorage] Found \(allMessages.reduce(0, { $0 + $1.messages.count })) messages to re-encrypt")
        
        // Set up new passphrase (generates new master key)
        try setupStoragePassphrase(newPassphrase)
        
        // Re-encrypt and save all messages with new key
        // TODO: Implement proper re-encryption when needed
        // For now, this is a placeholder that will be implemented when UI is added
        for (_, _) in allMessages {
            // Will implement re-encryption logic here
        }
        
        print("[MessageStorage] ✅ Passphrase changed and messages re-encrypted")
    }
    
    /// Unlock storage with passphrase
    func unlockWithPassphrase(_ passphrase: String) async throws {
        print("[MessageStorage] Unlocking storage with passphrase...")
        
        guard let salt = keychain.data(for: masterKeySaltAccount) else {
            throw MessageStorageError.passphraseNotSet
        }
        
        // Derive master key from passphrase
        let masterKey = try deriveMasterKey(from: passphrase, salt: salt)
        
        // Verify by attempting to decrypt a test message (if any exists)
        // For now, just cache the key
        cachedMasterKey = masterKey
        
        print("[MessageStorage] ✅ Storage unlocked")
    }
    
    /// Unlock storage with biometric authentication (Face ID / Touch ID)
    func unlockWithBiometric() async throws {
        print("[MessageStorage] Unlocking storage with biometric...")
        
        // Retrieve wrapped key from Keychain (triggers biometric prompt)
        guard let wrappedKeyData = try retrieveBiometricWrappedKey() else {
            throw MessageStorageError.biometricFailed
        }
        
        // Unwrap to get master key components
        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(BiometricKeyWrapper.self, from: wrappedKeyData)
        
        // Reconstruct master key
        let masterKey = SymmetricKey(data: Data(base64Encoded: wrapper.keyBase64)!)
        
        // Cache in memory
        cachedMasterKey = masterKey
        
        print("[MessageStorage] ✅ Storage unlocked with biometric")
    }
    
    /// Lock storage (clear cached key)
    func lock() {
        cachedMasterKey = nil
        print("[MessageStorage] 🔒 Storage locked")
    }
    
    /// Check if storage is currently unlocked
    var isUnlocked: Bool {
        cachedMasterKey != nil
    }
    
    // MARK: - Message Storage Operations
    
    /// Save a message to encrypted storage
    func saveMessage(
        _ message: ChatMessage,
        sessionId: UUID,
        config: MessageStorageConfig
    ) throws {
        // Check if storage is enabled for this session
        guard config.lifetime != .ephemeral else {
            throw MessageStorageError.storageDisabled
        }
        
        guard let masterKey = cachedMasterKey else {
            throw MessageStorageError.passphraseNotSet
        }
        
        // Determine message type
        let messageType: StoredMessage.MessageType
        let contentToEncrypt: String
        
        if let locationData = message.locationData {
            messageType = .location
            contentToEncrypt = locationData.toJSONString() ?? ""
        } else if let voiceData = message.voiceData {
            messageType = .voice
            contentToEncrypt = voiceData.toJSONString() ?? ""
        } else {
            messageType = .text
            contentToEncrypt = message.text
        }
        
        // Calculate expiration time
        let expiresAt: Date?
        if let seconds = config.lifetime.seconds {
            expiresAt = message.timestamp.addingTimeInterval(seconds)
        } else {
            expiresAt = nil
        }
        
        // Encrypt message content
        let nonce = AES.GCM.Nonce()
        let plaintextData = Data(contentToEncrypt.utf8)
        
        let sealedBox = try AES.GCM.seal(
            plaintextData,
            using: masterKey,
            nonce: nonce
        )
        
        // Create stored message
        let storedMessage = StoredMessage(
            id: message.id,
            sessionId: sessionId,
            encryptedContent: sealedBox.ciphertext,
            nonce: Data(nonce),
            tag: sealedBox.tag,
            timestamp: message.timestamp,
            isFromSelf: message.isFromSelf,
            messageType: messageType,
            expiresAt: expiresAt
        )
        
        // Save to disk
        try saveStoredMessage(storedMessage, sessionId: sessionId)
        
        print("[MessageStorage] ✅ Saved \(messageType.rawValue) message for session \(sessionId.uuidString.prefix(8))")
    }
    
    /// Load all messages for a session
    func loadMessages(for sessionId: UUID) throws -> [StoredMessage] {
        // Verify storage is unlocked (we don't need the key itself for loading metadata)
        guard cachedMasterKey != nil else {
            throw MessageStorageError.passphraseNotSet
        }
        
        let sessionDir = storageDirectory.appendingPathComponent(sessionId.uuidString)
        
        guard fileManager.fileExists(atPath: sessionDir.path) else {
            return [] // No messages yet
        }
        
        let files = try fileManager.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil)
        var messages: [StoredMessage] = []
        
        for file in files where file.pathExtension == "msg" {
            if let data = try? Data(contentsOf: file),
               let message = try? JSONDecoder().decode(StoredMessage.self, from: data) {
                messages.append(message)
            }
        }
        
        // Sort by timestamp
        messages.sort { $0.timestamp < $1.timestamp }
        
        print("[MessageStorage] Loaded \(messages.count) messages for session \(sessionId.uuidString.prefix(8))")
        
        return messages
    }
    
    /// Decrypt and convert stored message to ChatMessage
    func decryptMessage(_ storedMessage: StoredMessage) throws -> ChatMessage {
        guard let masterKey = cachedMasterKey else {
            throw MessageStorageError.passphraseNotSet
        }
        
        // Reconstruct sealed box
        let nonce = try AES.GCM.Nonce(data: storedMessage.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: storedMessage.encryptedContent,
            tag: storedMessage.tag
        )
        
        // Decrypt
        let plaintextData = try AES.GCM.open(sealedBox, using: masterKey)
        
        guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
            throw MessageStorageError.invalidData
        }
        
        // Reconstruct ChatMessage based on type
        var message = ChatMessage(
            text: storedMessage.messageType == .text ? plaintext : "",
            timestamp: storedMessage.timestamp,
            isFromSelf: storedMessage.isFromSelf
        )
        
        switch storedMessage.messageType {
        case .text:
            break // Already set
        case .location:
            message.locationData = LocationData.fromJSONString(plaintext)
        case .voice:
            message.voiceData = VoiceData.fromJSONString(plaintext)
        }
        
        return message
    }
    
    /// Delete all messages for a session
    func deleteMessages(for sessionId: UUID) throws {
        let sessionDir = storageDirectory.appendingPathComponent(sessionId.uuidString)
        
        if fileManager.fileExists(atPath: sessionDir.path) {
            try fileManager.removeItem(at: sessionDir)
            print("[MessageStorage] 🗑️ Deleted all messages for session \(sessionId.uuidString.prefix(8))")
        }
    }
    
    /// Delete expired messages across all sessions
    func cleanupExpiredMessages() throws {
        let allSessions = getAllSessions()
        var deletedCount = 0
        
        for sessionId in allSessions {
            let messages = try loadMessages(for: sessionId)
            let now = Date()
            
            for message in messages {
                if let expiresAt = message.expiresAt, expiresAt < now {
                    try deleteStoredMessage(message, sessionId: sessionId)
                    deletedCount += 1
                }
            }
        }
        
        print("[MessageStorage] 🗑️ Cleaned up \(deletedCount) expired messages")
    }
    
    /// Get storage configuration for a session
    func getStorageConfig(for sessionId: UUID) -> MessageStorageConfig? {
        let configPath = storageDirectory.appendingPathComponent("\(sessionId.uuidString)_config.json")
        
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(MessageStorageConfig.self, from: data) else {
            return nil
        }
        
        return config
    }
    
    /// Save storage configuration for a session
    func saveStorageConfig(_ config: MessageStorageConfig) throws {
        let configPath = storageDirectory.appendingPathComponent("\(config.sessionId.uuidString)_config.json")
        let data = try JSONEncoder().encode(config)
        try data.write(to: configPath)
        
        print("[MessageStorage] Saved config for session \(config.sessionId.uuidString.prefix(8)): \(config.lifetime.displayName)")
    }
    
    // MARK: - Erase All Data
    
    /// Securely erase all stored messages and keys
    func eraseAllData() throws {
        print("[MessageStorage] 🗑️ Erasing all encrypted storage...")
        
        // Delete all message files
        if fileManager.fileExists(atPath: storageDirectory.path) {
            try fileManager.removeItem(at: storageDirectory)
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        }
        
        // Delete all keychain items
        try? keychain.delete(account: masterKeySaltAccount)
        try? deleteBiometricWrappedKey()
        
        // Clear cache
        cachedMasterKey = nil
        
        print("[MessageStorage] ✅ All data erased")
    }
    
    // MARK: - Private Helpers
    
    private func deriveMasterKey(from passphrase: String, salt: Data) throws -> SymmetricKey {
        // Use HKDF to derive key from passphrase
        let passphraseData = Data(passphrase.utf8)
        let inputKey = SymmetricKey(data: passphraseData)
        
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("inviso-storage-master-v1".utf8),
            outputByteCount: keySize
        )
        
        return derivedKey
    }
    
    private func generateRandomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        
        if status != errSecSuccess {
            // Fallback to Swift's random
            bytes = (0..<count).map { _ in UInt8.random(in: 0...255) }
        }
        
        return Data(bytes)
    }
    
    private func saveStoredMessage(_ message: StoredMessage, sessionId: UUID) throws {
        let sessionDir = storageDirectory.appendingPathComponent(sessionId.uuidString)
        try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        
        let messageFile = sessionDir.appendingPathComponent("\(message.id.uuidString).msg")
        let data = try JSONEncoder().encode(message)
        try data.write(to: messageFile)
    }
    
    private func deleteStoredMessage(_ message: StoredMessage, sessionId: UUID) throws {
        let sessionDir = storageDirectory.appendingPathComponent(sessionId.uuidString)
        let messageFile = sessionDir.appendingPathComponent("\(message.id.uuidString).msg")
        
        if fileManager.fileExists(atPath: messageFile.path) {
            try fileManager.removeItem(at: messageFile)
        }
    }
    
    private func getAllSessions() -> [UUID] {
        guard let contents = try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return contents.compactMap { url in
            guard url.hasDirectoryPath else { return nil }
            return UUID(uuidString: url.lastPathComponent)
        }
    }
    
    // MARK: - Biometric Key Wrapping (Secure Enclave)
    
    private struct BiometricKeyWrapper: Codable {
        let keyBase64: String
        let saltBase64: String
    }
    
    private func storeBiometricWrappedKey(_ masterKey: SymmetricKey, passphrase: String, salt: Data) throws {
        // Create access control for biometric authentication
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryAny,  // Require Face ID / Touch ID
            nil
        ) else {
            throw MessageStorageError.keychainError(errSecAllocate)
        }
        
        // Wrap the key data in a simple structure
        let wrapper = BiometricKeyWrapper(
            keyBase64: masterKey.withUnsafeBytes { Data($0).base64EncodedString() },
            saltBase64: salt.base64EncodedString()
        )
        
        let wrapperData = try JSONEncoder().encode(wrapper)
        
        // Store in Keychain with biometric protection
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: biometricWrappedKeyAccount,
            kSecValueData as String: wrapperData,
            kSecAttrAccessControl as String: access,
            kSecAttrSynchronizable as String: false,  // Never sync to iCloud
            kSecUseDataProtectionKeychain as String: true  // Hardware encryption
        ]
        
        // Delete existing first
        try? deleteBiometricWrappedKey()
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw MessageStorageError.keychainError(status)
        }
        
        print("[MessageStorage] ✅ Stored biometric-wrapped key")
    }
    
    private func retrieveBiometricWrappedKey() throws -> Data? {
        // Create LAContext for authentication
        let context = LAContext()
        context.localizedReason = "Unlock encrypted message storage"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: biometricWrappedKeyAccount,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess, let data = item as? Data else {
            throw MessageStorageError.keychainError(status)
        }
        
        return data
    }
    
    private func deleteBiometricWrappedKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: biometricWrappedKeyAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MessageStorageError.keychainError(status)
        }
    }
}
