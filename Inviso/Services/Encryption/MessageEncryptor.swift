//
//  MessageEncryptor.swift
//  Inviso
//
//  AES-256-GCM encryption with HKDF ratchet for forward secrecy
//  Created by GitHub Copilot on 10/8/25.
//

import Foundation
import CryptoKit

/// Handles message encryption/decryption with forward secrecy via HKDF ratchet
final class MessageEncryptor {
    
    // MARK: - Public API
    
    /// Encrypt a plaintext message
    /// - Parameters:
    ///   - plaintext: Message to encrypt
    ///   - sessionKey: Session key derived from ECDH
    ///   - counter: Message counter (must increment for each message)
    ///   - direction: Send or receive (affects key derivation)
    /// - Returns: Encrypted wire format
    /// - Throws: EncryptionError if encryption fails
    func encrypt(
        _ plaintext: String,
        sessionKey: SymmetricKey,
        counter: UInt64,
        direction: MessageDirection
    ) throws -> MessageWireFormat {
        // 1. Derive message-specific key using HKDF ratchet
        let messageKey = try deriveMessageKey(
            sessionKey: sessionKey,
            counter: counter,
            direction: direction
        )
        
        // 2. Generate random nonce (12 bytes for AES-GCM)
        let nonce = AES.GCM.Nonce()
        
        // 3. Encrypt plaintext with AES-256-GCM
        let plaintextData = Data(plaintext.utf8)
        let sealedBox: AES.GCM.SealedBox
        
        do {
            sealedBox = try AES.GCM.seal(
                plaintextData,
                using: messageKey,
                nonce: nonce
            )
        } catch {
            throw EncryptionError.encryptionFailed("AES-GCM seal failed: \(error.localizedDescription)")
        }
        
        // 4. Extract ciphertext and authentication tag
        let ciphertext = sealedBox.ciphertext
        let tag = sealedBox.tag
        
        // 5. Securely delete message key (forward secrecy!)
        zeroMemory(messageKey)
        
        // 6. Create wire format
        let wireFormat = MessageWireFormat(
            version: 1,
            counter: counter,
            nonce: Data(nonce),
            ciphertext: ciphertext,
            tag: tag
        )
        
        print("[MessageEncryptor] Encrypted message (counter: \(counter), size: \(ciphertext.count) bytes)")
        
        return wireFormat
    }
    
    /// Decrypt a received message
    /// - Parameters:
    ///   - wireFormat: Encrypted wire format
    ///   - sessionKey: Session key derived from ECDH
    ///   - direction: Send or receive (affects key derivation)
    /// - Returns: Decrypted plaintext
    /// - Throws: EncryptionError if decryption fails
    func decrypt(
        _ wireFormat: MessageWireFormat,
        sessionKey: SymmetricKey,
        direction: MessageDirection
    ) throws -> String {
        // 1. Validate version
        guard wireFormat.v == 1 else {
            throw EncryptionError.invalidMessageVersion
        }
        
        // 2. Decode components
        guard let nonceData = wireFormat.nonceData,
              let ciphertextData = wireFormat.ciphertextData,
              let tagData = wireFormat.tagData else {
            throw EncryptionError.messageFormatInvalid
        }
        
        // 3. Validate sizes
        guard nonceData.count == EncryptionConstants.nonceSize else {
            throw EncryptionError.invalidNonce
        }
        
        guard tagData.count == EncryptionConstants.tagSize else {
            throw EncryptionError.invalidTag
        }
        
        // 4. Derive same message-specific key using HKDF ratchet
        let messageKey = try deriveMessageKey(
            sessionKey: sessionKey,
            counter: wireFormat.c,
            direction: direction
        )
        
        // 5. Reconstruct sealed box
        let nonce: AES.GCM.Nonce
        let sealedBox: AES.GCM.SealedBox
        
        do {
            nonce = try AES.GCM.Nonce(data: nonceData)
            sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: ciphertextData,
                tag: tagData
            )
        } catch {
            throw EncryptionError.invalidCiphertext
        }
        
        // 6. Decrypt with AES-256-GCM (automatically verifies authentication tag)
        let plaintextData: Data
        
        do {
            plaintextData = try AES.GCM.open(sealedBox, using: messageKey)
        } catch {
            // Authentication failed or tampering detected
            throw EncryptionError.authenticationFailed
        }
        
        // 7. Securely delete message key (forward secrecy!)
        zeroMemory(messageKey)
        
        // 8. Convert to string
        guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed("Invalid UTF-8 encoding")
        }
        
        print("[MessageEncryptor] Decrypted message (counter: \(wireFormat.c), size: \(plaintextData.count) bytes)")
        
        return plaintext
    }
    
    // MARK: - HKDF Ratchet
    
    /// Derive a message-specific key using HKDF (forward secrecy)
    /// - Parameters:
    ///   - sessionKey: Session key derived from ECDH
    ///   - counter: Message counter
    ///   - direction: Send or receive (ensures different key streams)
    /// - Returns: Derived message key
    /// - Throws: EncryptionError if derivation fails
    func deriveMessageKey(
        sessionKey: SymmetricKey,
        counter: UInt64,
        direction: MessageDirection
    ) throws -> SymmetricKey {
        // Construct HKDF info: "inviso-msg-v1" || direction || counter (big-endian)
        var info = EncryptionConstants.messageKeyInfoPrefix
        info.append(direction.rawValue)
        
        // Append counter as big-endian UInt64
        withUnsafeBytes(of: counter.bigEndian) { buffer in
            info.append(contentsOf: buffer)
        }
        
        // Derive message key using HKDF-SHA256
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: sessionKey,
            salt: Data(),  // Empty salt is acceptable for HKDF
            info: info,
            outputByteCount: EncryptionConstants.sessionKeySize
        )
        
        return derivedKey
    }
    
    // MARK: - Private Helpers
    
    /// Securely zero out symmetric key memory
    private func zeroMemory(_ key: SymmetricKey) {
        key.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            memset_s(
                UnsafeMutableRawPointer(mutating: baseAddress),
                ptr.count,
                0,
                ptr.count
            )
        }
    }
}
