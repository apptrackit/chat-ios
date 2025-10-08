//
//  EncryptionErrors.swift
//  Inviso
//
//  Encryption error types with localized descriptions
//  Created by GitHub Copilot on 10/8/25.
//

import Foundation

/// Comprehensive error types for encryption operations
enum EncryptionError: Error, LocalizedError, Equatable {
    // Key Generation & Exchange Errors
    case keypairGenerationFailed
    case invalidPublicKey
    case invalidPublicKeyLength
    case invalidPrivateKeyLength
    case publicKeyDecodingFailed
    case privateKeyNotFound
    case sessionKeyNotFound
    case keyExchangeTimeout
    case keyExchangeFailed(String)
    case peerPublicKeyMissing
    
    // Key Derivation Errors
    case sharedSecretDerivationFailed
    case sessionKeyDerivationFailed
    case messageKeyDerivationFailed
    
    // Encryption/Decryption Errors
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidCiphertext
    case invalidNonce
    case invalidTag
    case authenticationFailed
    
    // Message Validation Errors
    case replayAttack
    case counterGapTooLarge
    case invalidCounter
    case invalidMessageVersion
    case messageFormatInvalid
    
    // Keychain Errors
    case keychainStoreFailed(OSStatus)
    case keychainRetrieveFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
    case keychainUnknownError
    
    // State Errors
    case encryptionNotReady
    case sessionNotActive
    case invalidSessionState
    
    // MARK: - LocalizedError Implementation
    
    var errorDescription: String? {
        switch self {
        // Key Generation & Exchange
        case .keypairGenerationFailed:
            return "Failed to generate encryption key pair"
        case .invalidPublicKey:
            return "Invalid public key received"
        case .invalidPublicKeyLength:
            return "Public key has incorrect length"
        case .invalidPrivateKeyLength:
            return "Private key has incorrect length"
        case .publicKeyDecodingFailed:
            return "Failed to decode public key"
        case .privateKeyNotFound:
            return "Private key not found in secure storage"
        case .sessionKeyNotFound:
            return "Session key not found in secure storage"
        case .keyExchangeTimeout:
            return "Key exchange timed out"
        case .keyExchangeFailed(let reason):
            return "Key exchange failed: \(reason)"
        case .peerPublicKeyMissing:
            return "Peer's public key not received"
            
        // Key Derivation
        case .sharedSecretDerivationFailed:
            return "Failed to derive shared secret"
        case .sessionKeyDerivationFailed:
            return "Failed to derive session key"
        case .messageKeyDerivationFailed:
            return "Failed to derive message key"
            
        // Encryption/Decryption
        case .encryptionFailed(let reason):
            return "Encryption failed: \(reason)"
        case .decryptionFailed(let reason):
            return "Decryption failed: \(reason)"
        case .invalidCiphertext:
            return "Invalid ciphertext format"
        case .invalidNonce:
            return "Invalid nonce format"
        case .invalidTag:
            return "Invalid authentication tag"
        case .authenticationFailed:
            return "Message authentication failed - possible tampering"
            
        // Message Validation
        case .replayAttack:
            return "Potential replay attack detected"
        case .counterGapTooLarge:
            return "Message counter gap too large"
        case .invalidCounter:
            return "Invalid message counter"
        case .invalidMessageVersion:
            return "Unsupported message format version"
        case .messageFormatInvalid:
            return "Invalid message format"
            
        // Keychain
        case .keychainStoreFailed(let status):
            return "Failed to store key in Keychain (status: \(status))"
        case .keychainRetrieveFailed(let status):
            return "Failed to retrieve key from Keychain (status: \(status))"
        case .keychainDeleteFailed(let status):
            return "Failed to delete key from Keychain (status: \(status))"
        case .keychainUnknownError:
            return "Unknown Keychain error"
            
        // State
        case .encryptionNotReady:
            return "Encryption not ready - key exchange incomplete"
        case .sessionNotActive:
            return "No active session"
        case .invalidSessionState:
            return "Invalid session state"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .keyExchangeTimeout:
            return "Check your network connection and try reconnecting"
        case .replayAttack:
            return "This may indicate a security issue. Try reconnecting."
        case .authenticationFailed:
            return "Message may have been tampered with. Try reconnecting."
        case .encryptionNotReady:
            return "Wait for encryption setup to complete"
        case .keychainStoreFailed, .keychainRetrieveFailed:
            return "Check device storage and security settings"
        default:
            return "Try reconnecting to the session"
        }
    }
    
    /// Whether this error is critical and requires connection termination
    var isCritical: Bool {
        switch self {
        case .replayAttack, .authenticationFailed, .counterGapTooLarge:
            return true
        default:
            return false
        }
    }
    
    /// Whether this error should be shown to the user
    var isUserFacing: Bool {
        switch self {
        case .encryptionNotReady, .keyExchangeTimeout, .decryptionFailed, .encryptionFailed:
            return true
        default:
            return false
        }
    }
}
