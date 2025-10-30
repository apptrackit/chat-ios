//
//  EncryptionModels.swift
//  Inviso
//
//  End-to-end encryption models and data structures
//  Created by GitHub Copilot on 10/8/25.
//

import Foundation
import CryptoKit

// MARK: - Message Wire Format

/// JSON structure sent over WebRTC DataChannel for encrypted messages
struct MessageWireFormat: Codable, Equatable {
    /// Protocol version (currently 1)
    let v: UInt8
    
    /// Message counter (monotonic, prevents replay attacks)
    let c: UInt64
    
    /// Nonce/IV for AES-GCM (12 bytes, base64 encoded)
    let n: String
    
    /// Ciphertext (variable length, base64 encoded)
    let d: String
    
    /// Authentication tag (16 bytes, base64 encoded)
    let t: String
    
    init(version: UInt8, counter: UInt64, nonce: Data, ciphertext: Data, tag: Data) {
        self.v = version
        self.c = counter
        self.n = nonce.base64EncodedString()
        self.d = ciphertext.base64EncodedString()
        self.t = tag.base64EncodedString()
    }
    
    /// Decoded nonce data
    var nonceData: Data? {
        Data(base64Encoded: n)
    }
    
    /// Decoded ciphertext data
    var ciphertextData: Data? {
        Data(base64Encoded: d)
    }
    
    /// Decoded tag data
    var tagData: Data? {
        Data(base64Encoded: t)
    }
}

// MARK: - Encryption State

/// Per-session encryption state (in-memory only)
struct EncryptionState {
    /// Session key derived from ECDH (stored in Keychain, referenced here)
    var sessionKey: SymmetricKey?
    
    /// Send message counter (increments with each sent message)
    var sendCounter: UInt64
    
    /// Receive message counter (tracks highest received counter)
    var receiveCounter: UInt64
    
    /// Whether key exchange has completed successfully
    var keyExchangeComplete: Bool
    
    /// Timestamp when key exchange started (for timeout detection)
    var keyExchangeStartedAt: Date?
    
    init(sendCounter: UInt64 = 0, receiveCounter: UInt64 = 0, keyExchangeComplete: Bool = false) {
        self.sendCounter = sendCounter
        self.receiveCounter = receiveCounter
        self.keyExchangeComplete = keyExchangeComplete
        self.keyExchangeStartedAt = Date()
    }
}

// MARK: - Message Direction

/// Direction of message (used in HKDF derivation for separate key streams)
enum MessageDirection: UInt8 {
    case send = 0x01
    case receive = 0x02
}

// MARK: - Key Types

/// Types of cryptographic keys stored in Keychain
enum KeyType: String {
    case privateKey = "privateKey"
    case sessionKey = "sessionKey"
}

// MARK: - Key Exchange Messages

/// WebSocket signaling message for public key exchange
struct KeyExchangeMessage: Codable {
    let type: String
    let publicKey: String  // Base64-encoded public key (32 bytes)
    let sessionId: String  // Room ID for key association
    let timestamp: TimeInterval
    
    init(publicKey: String, sessionId: String, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.type = "key_exchange"
        self.publicKey = publicKey
        self.sessionId = sessionId
        self.timestamp = timestamp
    }
}

/// WebSocket signaling message for confirming key exchange completion
struct KeyExchangeCompleteMessage: Codable {
    let type: String
    let sessionId: String
    let timestamp: TimeInterval
    
    init(sessionId: String, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.type = "key_exchange_complete"
        self.sessionId = sessionId
        self.timestamp = timestamp
    }
}

// MARK: - Message Lifetime Negotiation

/// WebSocket signaling message for proposing message lifetime
struct LifetimeProposalMessage: Codable {
    let type: String
    let sessionId: String
    let lifetime: String // MessageLifetime rawValue
    let proposedAt: Double // Unix timestamp
    
    init(sessionId: String, lifetime: String, proposedAt: Double = Date().timeIntervalSince1970) {
        self.type = "lifetime_proposal"
        self.sessionId = sessionId
        self.lifetime = lifetime
        self.proposedAt = proposedAt
    }
}

/// WebSocket signaling message for accepting lifetime proposal
struct LifetimeAcceptMessage: Codable {
    let type: String
    let sessionId: String
    let lifetime: String // MessageLifetime rawValue
    let acceptedAt: Double // Unix timestamp
    
    init(sessionId: String, lifetime: String, acceptedAt: Double = Date().timeIntervalSince1970) {
        self.type = "lifetime_accept"
        self.sessionId = sessionId
        self.lifetime = lifetime
        self.acceptedAt = acceptedAt
    }
}

/// WebSocket signaling message for rejecting lifetime proposal
struct LifetimeRejectMessage: Codable {
    let type: String
    let sessionId: String
    let reason: String?
    
    init(sessionId: String, reason: String? = nil) {
        self.type = "lifetime_reject"
        self.sessionId = sessionId
        self.reason = reason
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let keyExchangeReceived = Notification.Name("keyExchangeReceived")
    static let keyExchangeCompleteReceived = Notification.Name("keyExchangeCompleteReceived")
    static let encryptionFailed = Notification.Name("encryptionFailed")
    
    // Message lifetime negotiation
    static let lifetimeProposalReceived = Notification.Name("lifetimeProposalReceived")
    static let lifetimeAcceptReceived = Notification.Name("lifetimeAcceptReceived")
    static let lifetimeRejectReceived = Notification.Name("lifetimeRejectReceived")
    static let lifetimeProposalCancelled = Notification.Name("lifetimeProposalCancelled")
}

// MARK: - Constants

enum EncryptionConstants {
    /// Key exchange timeout (10 seconds)
    static let keyExchangeTimeout: TimeInterval = 10.0
    
    /// Maximum counter gap allowed (prevents out-of-order attacks)
    static let maxCounterGap: UInt64 = 1000
    
    /// HKDF info string for session key derivation
    static let sessionKeyInfo = Data("inviso-session-v1".utf8)
    
    /// HKDF info prefix for message key derivation
    static let messageKeyInfoPrefix = Data("inviso-msg-v1".utf8)
    
    /// Expected public key size (X25519)
    static let publicKeySize = 32
    
    /// Expected private key size (X25519)
    static let privateKeySize = 32
    
    /// Expected session key size (AES-256)
    static let sessionKeySize = 32
    
    /// Expected nonce size (AES-GCM)
    static let nonceSize = 12
    
    /// Expected tag size (AES-GCM)
    static let tagSize = 16
}
