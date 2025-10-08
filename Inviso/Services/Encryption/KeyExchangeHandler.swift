//
//  KeyExchangeHandler.swift
//  Inviso
//
//  ECDH (X25519) key exchange orchestration
//  Created by GitHub Copilot on 10/8/25.
//

import Foundation
import CryptoKit

/// Handles ECDH key exchange and session key derivation
final class KeyExchangeHandler {
    private let keychainService = EncryptionKeychain.shared
    
    // MARK: - Public API
    
    /// Generate ephemeral ECDH keypair for a session
    /// - Parameter sessionId: Session identifier
    /// - Returns: Public key to send to peer
    /// - Throws: EncryptionError if generation or storage fails
    func generateKeypair(sessionId: UUID) throws -> Curve25519.KeyAgreement.PublicKey {
        print("[KeyExchange] Generating ECDH keypair for session \(sessionId.uuidString.prefix(8))")
        
        // 1. Generate ephemeral X25519 private key
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        
        // 2. Validate key size
        guard privateKey.rawRepresentation.count == EncryptionConstants.privateKeySize else {
            throw EncryptionError.invalidPrivateKeyLength
        }
        
        // 3. Store private key in Keychain
        do {
            try keychainService.setKey(
                privateKey.rawRepresentation,
                for: .privateKey,
                sessionId: sessionId
            )
        } catch {
            print("[KeyExchange] Failed to store private key: \(error)")
            throw EncryptionError.keypairGenerationFailed
        }
        
        // 4. Return public key for transmission to peer
        let publicKey = privateKey.publicKey
        print("[KeyExchange] Generated public key: \(publicKey.rawRepresentation.base64EncodedString().prefix(16))...")
        
        return publicKey
    }
    
    /// Derive session key from peer's public key using ECDH + HKDF
    /// - Parameters:
    ///   - peerPublicKey: Public key received from peer
    ///   - sessionId: Session identifier
    /// - Returns: Derived session key (also stored in Keychain)
    /// - Throws: EncryptionError if derivation or storage fails
    func deriveSessionKey(
        peerPublicKey: Curve25519.KeyAgreement.PublicKey,
        sessionId: UUID
    ) throws -> SymmetricKey {
        print("[KeyExchange] Deriving session key for session \(sessionId.uuidString.prefix(8))")
        
        // 1. Retrieve private key from Keychain
        guard let privateKeyData = try keychainService.getKey(
            for: .privateKey,
            sessionId: sessionId
        ) else {
            throw EncryptionError.privateKeyNotFound
        }
        
        // 2. Reconstruct private key
        let privateKey: Curve25519.KeyAgreement.PrivateKey
        do {
            privateKey = try Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: privateKeyData
            )
        } catch {
            print("[KeyExchange] Failed to reconstruct private key: \(error)")
            throw EncryptionError.privateKeyNotFound
        }
        
        // 3. Perform ECDH to derive shared secret
        let sharedSecret: SharedSecret
        do {
            sharedSecret = try privateKey.sharedSecretFromKeyAgreement(
                with: peerPublicKey
            )
        } catch {
            print("[KeyExchange] ECDH failed: \(error)")
            throw EncryptionError.sharedSecretDerivationFailed
        }
        
        // 4. Derive session key from shared secret using HKDF-SHA256
        let sessionKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),  // Empty salt is acceptable
            sharedInfo: EncryptionConstants.sessionKeyInfo,
            outputByteCount: EncryptionConstants.sessionKeySize
        )
        
        // 5. Store session key in Keychain
        do {
            try keychainService.setKey(
                sessionKey.withUnsafeBytes { Data($0) },
                for: .sessionKey,
                sessionId: sessionId
            )
        } catch {
            print("[KeyExchange] Failed to store session key: \(error)")
            throw EncryptionError.sessionKeyDerivationFailed
        }
        
        print("[KeyExchange] Session key derived and stored successfully")
        
        return sessionKey
    }
    
    /// Retrieve existing session key from Keychain
    /// - Parameter sessionId: Session identifier
    /// - Returns: Session key or nil if not found
    /// - Throws: EncryptionError if retrieval fails
    func getSessionKey(sessionId: UUID) throws -> SymmetricKey? {
        guard let keyData = try keychainService.getKey(
            for: .sessionKey,
            sessionId: sessionId
        ) else {
            return nil
        }
        
        return SymmetricKey(data: keyData)
    }
    
    /// Validate peer's public key format and size
    /// - Parameter publicKeyData: Raw public key data
    /// - Returns: Validated public key
    /// - Throws: EncryptionError if validation fails
    func validatePeerPublicKey(_ publicKeyData: Data) throws -> Curve25519.KeyAgreement.PublicKey {
        // 1. Check size (X25519 public keys are always 32 bytes)
        guard publicKeyData.count == EncryptionConstants.publicKeySize else {
            print("[KeyExchange] Invalid public key size: \(publicKeyData.count) bytes")
            throw EncryptionError.invalidPublicKeyLength
        }
        
        // 2. Try to construct public key
        let publicKey: Curve25519.KeyAgreement.PublicKey
        do {
            publicKey = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: publicKeyData
            )
        } catch {
            print("[KeyExchange] Public key construction failed: \(error)")
            throw EncryptionError.publicKeyDecodingFailed
        }
        
        return publicKey
    }
    
    /// Delete keys for a specific session
    /// - Parameter sessionId: Session identifier
    func deleteKeys(for sessionId: UUID) {
        do {
            try keychainService.deleteKeys(for: sessionId)
            print("[KeyExchange] Deleted keys for session \(sessionId.uuidString.prefix(8))")
        } catch {
            print("[KeyExchange] Failed to delete keys: \(error)")
        }
    }
}
