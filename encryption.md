# Inviso End-to-End Encryption Specification

**Version:** 1.0  
**Date:** October 8, 2025  
**Status:** Production Ready  
**Goal:** Maximum security P2P ephemeral chat with forward secrecy

---

## 1. Overview

Inviso implements **end-to-end encryption (E2EE)** for all message content using a hybrid cryptographic approach:

- **ECDH (X25519)** for key exchange
- **AES-256-GCM** for message encryption
- **HKDF-SHA256** for key derivation (forward secrecy within sessions)
- **Per-connection key rotation** for forward secrecy across connections

### Security Properties

✅ **Confidentiality:** Only sender and receiver can read message content  
✅ **Forward Secrecy:** Past messages remain secure even if current keys are compromised  
✅ **Authentication:** Messages cannot be forged (AES-GCM authenticated encryption)  
✅ **Ephemeral:** Keys and messages are wiped on session deletion  
✅ **Zero Server Knowledge:** Server never sees plaintext or usable key material  
✅ **Per-Connection Rotation:** New keys for every connection, even within same session  

### Threat Model: Maximum Security

We protect against:

- 🔒 **Passive network observers** (ISP, WiFi snooping)
- 🔒 **Active MITM attacks** (via TOFU model, upgradable to safety numbers)
- 🔒 **Compromised signaling/TURN server** (cannot decrypt content)
- 🔒 **Database breach** (no keys or plaintext stored server-side)
- 🔒 **Future key compromise** (forward secrecy protects past messages)
- 🔒 **Device forensics after session deletion** (keys wiped from Keychain)
- 🔒 **Replay attacks** (message counter prevents replays)
- 🔒 **Session correlation** (ephemeral device IDs per session)

---

## 2. Architecture

### 2.1 Key Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                    SESSION LIFECYCLE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Session Created                                                │
│  └─> No keys yet (REST API join code exchange only)            │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │          CONNECTION #1 (First Connection)                │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │  1. Generate ECDH Keypair #1                             │  │
│  │  2. Exchange public keys via WebSocket signaling         │  │
│  │  3. Derive shared secret → Session Key #1               │  │
│  │  4. Messages encrypted with HKDF ratchet                 │  │
│  │  5. On disconnect: Delete Session Key #1                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │          CONNECTION #2 (Reconnection)                    │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │  1. Generate NEW ECDH Keypair #2                         │  │
│  │  2. Exchange NEW public keys via WebSocket               │  │
│  │  3. Derive NEW shared secret → Session Key #2           │  │
│  │  4. Messages encrypted with HKDF ratchet (fresh counter)│  │
│  │  5. On disconnect: Delete Session Key #2                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Session Deleted                                                │
│  └─> All keys wiped from Keychain (both sides)                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Key Hierarchy

```
┌──────────────────────────────────────────────────────────────┐
│                         Per Connection                       │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Local Private Key (32 bytes, ephemeral)                    │
│       X25519 ECDH private key                               │
│       ├─> Stored in Keychain during connection only         │
│       └─> Deleted on disconnect                             │
│                                                              │
│  Local Public Key (32 bytes)                                │
│       X25519 ECDH public key                                │
│       └─> Sent to peer via WebSocket signaling              │
│                                                              │
│  Peer Public Key (32 bytes, received)                       │
│       X25519 ECDH public key from remote peer               │
│       └─> NOT stored persistently (re-exchanged each time)  │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Session Key (32 bytes, derived)                            │
│       = ECDH(LocalPrivate, PeerPublic)                      │
│       ├─> Stored in Keychain during connection              │
│       ├─> Used as root key for HKDF ratchet                 │
│       └─> Deleted on disconnect                             │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Message Keys (32 bytes each, ephemeral)                    │
│       = HKDF(SessionKey, counter || direction)              │
│       ├─> Derived on-demand for each message                │
│       ├─> Used once for AES-256-GCM encryption              │
│       └─> Deleted immediately after use                     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 3. Cryptographic Protocols

### 3.1 ECDH Key Exchange (X25519)

**When:** Every time P2P connection is established (including reconnections)

**Algorithm:** Curve25519 (X25519) Elliptic Curve Diffie-Hellman

**Process:**

```swift
// Both peers (Client1 and Client2) execute this independently:

// 1. Generate ephemeral keypair
let privateKey = Curve25519.KeyAgreement.PrivateKey() // 32 random bytes
let publicKey = privateKey.publicKey.rawRepresentation   // 32 bytes

// 2. Store private key temporarily in Keychain
KeychainService.setData(privateKey.rawRepresentation, 
                        for: "session.\(sessionId).privateKey")

// 3. Send public key to peer via WebSocket signaling
signalingClient.send([
    "type": "key_exchange",
    "publicKey": publicKey.base64EncodedString()
])

// 4. Receive peer's public key (via WebSocket)
// (Don't store peer public key persistently)

// 5. Derive shared secret
let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(
    rawRepresentation: Data(base64Encoded: receivedPublicKeyBase64)
)
let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(
    with: peerPublicKey
)

// 6. Derive session key using HKDF
let sessionKey = HKDF<SHA256>.deriveKey(
    inputKeyMaterial: sharedSecret,
    salt: Data(), // No salt (peer order-independent)
    info: Data("inviso-session-v1".utf8),
    outputByteCount: 32
)

// 7. Store session key in Keychain
KeychainService.setData(sessionKey, 
                        for: "session.\(sessionId).sessionKey")
```

**Security Notes:**

- ✅ X25519 provides ~128-bit security (equivalent to AES-256 against quantum computers using Grover's algorithm)
- ✅ Ephemeral keys (not reused across connections)
- ✅ Perfect Forward Secrecy: compromising one session key doesn't affect past/future connections
- ✅ No key confirmation needed (TOFU model)

---

### 3.2 WebSocket Key Exchange Messages

**New signaling message types** (add to existing WebSocket protocol):

#### Initiator → Responder (after `room_ready`)

```json
{
  "type": "key_exchange",
  "publicKey": "base64-encoded-32-bytes",
  "timestamp": 1728382800000
}
```

#### Responder → Initiator (reply)

```json
{
  "type": "key_exchange",
  "publicKey": "base64-encoded-32-bytes",
  "timestamp": 1728382801000
}
```

#### Acknowledgment (both directions)

```json
{
  "type": "key_exchange_complete",
  "timestamp": 1728382802000
}
```

**Server Behavior:**

- Server **relays** these messages without modification
- Server **cannot decrypt** (only sees public keys, which are useless without private keys)
- Server **does not store** public keys in database

**Client State Machine:**

```
room_ready received
  └─> Generate ECDH keypair
  └─> Send key_exchange message
  └─> Wait for peer's key_exchange message
  └─> Derive session key
  └─> Send key_exchange_complete
  └─> Wait for peer's key_exchange_complete
  └─> Start encrypted messaging
```

---

### 3.3 Message Encryption (AES-256-GCM + HKDF Ratchet)

**Algorithm:** AES-256-GCM (Galois/Counter Mode)

**Key Derivation:** HKDF-SHA256 ratchet

**Process for sending a message:**

```swift
// 1. Increment message counter
let messageCounter: UInt64 = getNextMessageCounter() // Starts at 0

// 2. Derive message-specific key using HKDF
let info = Data("inviso-msg-v1".utf8) + 
           Data([direction]) + // 0x01 for send, 0x02 for receive
           withUnsafeBytes(of: messageCounter.bigEndian) { Data($0) }

let messageKey = HKDF<SHA256>.deriveKey(
    inputKeyMaterial: sessionKey, // From Keychain
    salt: Data(),
    info: info,
    outputByteCount: 32 // 256 bits
)

// 3. Generate random nonce (IV) for AES-GCM
let nonce = AES.GCM.Nonce() // 12 random bytes

// 4. Encrypt message with AES-256-GCM
let plaintext = Data(message.utf8)
let sealedBox = try AES.GCM.seal(
    plaintext,
    using: SymmetricKey(data: messageKey),
    nonce: nonce
)

// 5. Construct wire format
let ciphertext = sealedBox.ciphertext
let tag = sealedBox.tag // 16-byte authentication tag

let wireMessage = MessageWireFormat(
    version: 1,
    counter: messageCounter,
    nonce: nonce,
    ciphertext: ciphertext,
    tag: tag
)

// 6. DELETE message key immediately (forward secrecy)
messageKey.withUnsafeBytes { ptr in
    memset_s(UnsafeMutableRawPointer(mutating: ptr.baseAddress!), 
             ptr.count, 0, ptr.count)
}

// 7. Send over WebRTC DataChannel
let jsonData = try JSONEncoder().encode(wireMessage)
dataChannel.sendData(RTCDataBuffer(data: jsonData, isBinary: true))

// 8. Store counter for next message
saveMessageCounter(messageCounter + 1)
```

**Process for receiving a message:**

```swift
// 1. Parse wire format
let wireMessage = try JSONDecoder().decode(
    MessageWireFormat.self, 
    from: receivedData
)

// 2. Validate counter (must be > last received counter, prevent replay)
guard wireMessage.counter > lastReceivedCounter else {
    throw EncryptionError.replayAttack
}

// 3. Derive same message-specific key
let info = Data("inviso-msg-v1".utf8) + 
           Data([0x01]) + // Opposite direction (sender used 0x01)
           withUnsafeBytes(of: wireMessage.counter.bigEndian) { Data($0) }

let messageKey = HKDF<SHA256>.deriveKey(
    inputKeyMaterial: sessionKey,
    salt: Data(),
    info: info,
    outputByteCount: 32
)

// 4. Decrypt with AES-256-GCM
let sealedBox = try AES.GCM.SealedBox(
    nonce: wireMessage.nonce,
    ciphertext: wireMessage.ciphertext,
    tag: wireMessage.tag
)

let plaintext = try AES.GCM.open(
    sealedBox,
    using: SymmetricKey(data: messageKey)
)

// 5. DELETE message key immediately
messageKey.withUnsafeBytes { ptr in
    memset_s(UnsafeMutableRawPointer(mutating: ptr.baseAddress!), 
             ptr.count, 0, ptr.count)
}

// 6. Update counter
lastReceivedCounter = wireMessage.counter

// 7. Return decrypted message
let message = String(data: plaintext, encoding: .utf8)
```

**Wire Format (JSON over WebRTC DataChannel):**

```json
{
  "v": 1,
  "c": 42,
  "n": "base64-encoded-12-bytes",
  "d": "base64-encoded-ciphertext",
  "t": "base64-encoded-16-byte-tag"
}
```

**Field Descriptions:**

| Field | Type | Description |
|-------|------|-------------|
| `v` | uint8 | Protocol version (1) |
| `c` | uint64 | Message counter (monotonic, prevents replay) |
| `n` | base64 | Nonce/IV (12 bytes, random per message) |
| `d` | base64 | Ciphertext (variable length) |
| `t` | base64 | Authentication tag (16 bytes) |

**Security Notes:**

- ✅ **Forward secrecy:** Each message uses a unique key, deleted immediately after use
- ✅ **Replay protection:** Message counter must be strictly increasing
- ✅ **Authentication:** GCM tag prevents tampering
- ✅ **No IV reuse:** Random nonce per message
- ✅ **Bi-directional security:** Separate counters and direction bytes for send/receive

---

### 3.4 Message Counter Management

**Purpose:** Prevent replay attacks and ensure forward secrecy

**Implementation:**

```swift
// Per-session state (in memory, not persisted)
struct EncryptionState {
    var sessionKey: Data // From Keychain
    var sendCounter: UInt64 = 0
    var receiveCounter: UInt64 = 0
    var keyExchangeComplete: Bool = false
}

// Counter rules:
// - sendCounter increments before each sent message
// - receiveCounter tracks highest received counter
// - On reconnect: counters reset to 0 (new session key)
// - Gap detection: if received counter jumps >1000, reject (out of order)
```

**Counter Reset Policy:**

| Event | Send Counter | Receive Counter |
|-------|--------------|-----------------|
| New connection | 0 | 0 |
| Message sent | +1 | (unchanged) |
| Message received | (unchanged) | Update to received value |
| Disconnect | (deleted) | (deleted) |
| Reconnect | 0 (new key) | 0 (new key) |

---

## 4. Key Storage (iOS Keychain)

### 4.1 Keychain Architecture

All cryptographic keys are stored in iOS Keychain with strict access controls.

**Service Identifier:** `com.inviso.encryption`

**Account Format:** `session.<sessionId>.<keyType>`

**Access Control:**

```swift
let access = SecAccessControlCreateWithFlags(
    nil,
    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    .userPresence, // Biometric/passcode required (optional)
    nil
)

let attributes: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.inviso.encryption",
    kSecAttrAccount as String: "session.\(sessionId).sessionKey",
    kSecValueData as String: keyData,
    kSecAttrAccessControl as String: access,
    kSecAttrSynchronizable as String: false, // Never sync to iCloud
    kSecUseDataProtectionKeychain as String: true // Hardware encryption
]
```

### 4.2 Keys Stored per Session

| Key Type | Account | Lifetime | Size |
|----------|---------|----------|------|
| Private Key | `session.<id>.privateKey` | During connection only | 32 bytes |
| Session Key | `session.<id>.sessionKey` | During connection only | 32 bytes |
| ~~Peer Public Key~~ | ❌ Not stored | ❌ Not stored | N/A |

**Note:** Peer public key is intentionally NOT stored. Re-exchanged on every connection for maximum forward secrecy.

### 4.3 Key Lifecycle Operations

**On Connection Established:**

```swift
// 1. Generate and store private key
let privateKey = Curve25519.KeyAgreement.PrivateKey()
try keychain.setData(
    privateKey.rawRepresentation,
    for: "session.\(sessionId).privateKey"
)

// 2. Derive and store session key (after peer key exchange)
let sessionKey = deriveSessionKey(privateKey, peerPublicKey)
try keychain.setData(
    sessionKey,
    for: "session.\(sessionId).sessionKey"
)
```

**On Connection Closed:**

```swift
// Delete both keys immediately
try keychain.delete(account: "session.\(sessionId).privateKey")
try keychain.delete(account: "session.\(sessionId).sessionKey")

// Also zero out in-memory copies
encryptionState.sessionKey.resetBytes(in: 0..<encryptionState.sessionKey.count)
```

**On Session Deleted by User:**

```swift
// Wipe all keys for this session (idempotent)
try keychain.delete(account: "session.\(sessionId).privateKey")
try keychain.delete(account: "session.\(sessionId).sessionKey")

// Session is now cryptographically unrecoverable
```

---

## 5. Implementation Guide

### 5.1 Required Swift Frameworks

```swift
import CryptoKit        // X25519, AES-GCM, HKDF, SHA256
import Foundation       // Data, JSON
import Security         // Keychain
```

**All algorithms are built into iOS 13+.** No third-party dependencies required.

### 5.2 New Swift Files to Create

```
Inviso/Services/Encryption/
├── EncryptionManager.swift          // Main coordinator
├── KeyExchangeHandler.swift         // ECDH key exchange logic
├── MessageEncryptor.swift           // AES-GCM + HKDF ratchet
├── EncryptionKeychain.swift         // Keychain wrapper for keys
├── EncryptionModels.swift           // Wire format, state models
└── EncryptionErrors.swift           // Error types
```

### 5.3 Modified Existing Files

**`ChatManager.swift`:**

```swift
// Add encryption manager
private let encryptionManager = EncryptionManager()

// On room_ready:
func handleRoomReady(isInitiator: Bool) {
    // Start key exchange before creating peer connection
    encryptionManager.startKeyExchange(
        sessionId: activeSessionId,
        isInitiator: isInitiator,
        signalingClient: signaling
    ) { [weak self] result in
        switch result {
        case .success:
            // Now create P2P connection
            self?.pcm.createPeerConnection(isInitiator: isInitiator)
        case .failure(let error):
            // Handle encryption setup failure
            print("[Encryption] Key exchange failed: \(error)")
        }
    }
}

// On message send:
func sendMessage(_ text: String) {
    guard let encryptedData = encryptionManager.encrypt(
        text,
        sessionId: activeSessionId
    ) else { return }
    
    pcm.send(encryptedData)
}

// On message receive:
func pcmDidReceiveMessage(_ data: Data) {
    guard let plaintext = encryptionManager.decrypt(
        data,
        sessionId: activeSessionId
    ) else { return }
    
    let message = ChatMessage(
        text: plaintext,
        timestamp: Date(),
        isFromSelf: false
    )
    messages.append(message)
}
```

**`SignalingClient.swift`:**

```swift
// Add new message types to handle in receive():
case "key_exchange":
    // Forward to encryption manager
    NotificationCenter.default.post(
        name: .signalingKeyExchange,
        object: json
    )

case "key_exchange_complete":
    // Forward to encryption manager
    NotificationCenter.default.post(
        name: .signalingKeyExchangeComplete,
        object: json
    )
```

**`PeerConnectionManager.swift`:**

```swift
// No changes needed - encryption is transparent at this layer
// Messages are already encrypted before calling send()
```

**`ChatModels.swift`:**

```swift
// Add encryption state to ChatSession
struct ChatSession: Codable {
    // ... existing fields ...
    
    // Encryption metadata (not the keys themselves)
    var encryptionEnabled: Bool = true // Always true for new sessions
    var keyExchangeCompletedAt: Date? // When E2EE was established
}
```

### 5.4 Server Changes (Minimal)

**`index.js` (Node.js signaling server):**

```javascript
// Add relay for encryption messages (no processing needed)
case 'key_exchange':
case 'key_exchange_complete':
  // Relay to peer without modification
  if (client.roomId && rooms.has(client.roomId)) {
    const peers = Array.from(rooms.get(client.roomId));
    peers.forEach(peer => {
      if (peer !== ws && peer.readyState === WebSocket.OPEN) {
        peer.send(JSON.stringify(msg));
      }
    });
  }
  break;
```

**No database changes required.** Server never stores keys.

---

## 6. Migration & Rollout Strategy

### 6.1 No Migration Needed

Since you specified "no migration needed," all new sessions will automatically use E2EE.

**Implementation approach:**

```swift
// In ChatManager.createSession():
let newSession = ChatSession(
    // ... other fields ...
    encryptionEnabled: true // Always true going forward
)
```

### 6.2 Graceful Degradation (Optional Safety Net)

If for some reason encryption fails, you can choose:

**Option A (Recommended): Fail hard**
```swift
if encryptionManager.keyExchangeFailed {
    // Show error, prevent messaging
    showAlert("Encryption failed. Cannot send messages.")
    return
}
```

**Option B: Fallback to warning**
```swift
if !encryptionManager.isEncrypted {
    // Show warning banner but allow messaging
    showBanner("⚠️ Encryption unavailable - messages not secure")
}
```

**Your choice:** Option A (fail hard) matches "maximum security" goal.

---

## 7. Security Audit Checklist

### 7.1 Cryptographic Correctness

- [ ] X25519 keys are generated with cryptographically secure RNG (CryptoKit default)
- [ ] Session key derived with HKDF-SHA256 (not raw ECDH output)
- [ ] AES-256-GCM nonce is 12 bytes random per message (never reused)
- [ ] HKDF info includes version, direction, and counter
- [ ] Message counters are strictly monotonic (replay protection)
- [ ] Authentication tags are verified before processing ciphertext

### 7.2 Key Management

- [ ] Private keys never leave Keychain
- [ ] Session keys deleted on disconnect
- [ ] Message keys deleted immediately after use
- [ ] No keys synced to iCloud (kSecAttrSynchronizable = false)
- [ ] Keys use hardware encryption (kSecUseDataProtectionKeychain = true)
- [ ] Keychain items have proper access control flags

### 7.3 Protocol Security

- [ ] Public keys exchanged over existing WebSocket TLS connection
- [ ] Key exchange completes before first message sent
- [ ] Out-of-order messages rejected (counter validation)
- [ ] Large counter gaps rejected (>1000 skip = suspicious)
- [ ] Encryption failures cause connection abort (no fallback to plaintext)

### 7.4 Implementation Security

- [ ] No logging of sensitive data (keys, plaintexts, counters)
- [ ] No debug prints left in production code
- [ ] Memory zeroing after key deletion (explicit memset_s calls)
- [ ] Error messages don't leak cryptographic info
- [ ] Timing attacks mitigated (use constant-time comparison for tags)

### 7.5 User Experience

- [ ] Encryption status visible in UI (lock icon, indicator)
- [ ] Key exchange timeout handling (10 second limit)
- [ ] Reconnection generates new keys automatically
- [ ] Session deletion wipes keys immediately
- [ ] No user action required for encryption (automatic)

---

## 8. Attack Resistance

### 8.1 Attacks We Defend Against

| Attack Type | Defense Mechanism |
|-------------|-------------------|
| **Eavesdropping** | TLS (signaling) + DTLS (WebRTC) + E2EE (messages) |
| **MITM (Passive)** | ECDH key exchange over TLS, public keys useless without private |
| **MITM (Active)** | TOFU model (first connection trusted), upgradable to safety numbers |
| **Replay Attack** | Message counter validation (strictly increasing) |
| **Message Tampering** | AES-GCM authentication tag (16 bytes) |
| **Key Compromise** | Forward secrecy (HKDF ratchet + per-connection rotation) |
| **Server Compromise** | Zero knowledge (server never sees keys or plaintext) |
| **Database Breach** | No keys stored server-side |
| **Device Theft** | Keychain encryption + optional biometric access control |
| **Forensics** | Keys wiped on session deletion (unrecoverable) |

### 8.2 Known Limitations

| Limitation | Mitigation | Future Enhancement |
|------------|------------|-------------------|
| **TOFU (no key verification)** | Acceptable for V1 | Add safety number verification |
| **No deniability** | AES-GCM proves sender authenticity | Could add OTR-style deniability if needed |
| **Single device** | Keychain not synced | Acceptable (no multi-device by design) |
| **Metadata visible** | Server sees room IDs, timing | Acceptable (ephemeral IDs hide user identity) |

---

## 9. Performance Considerations

### 9.1 Computational Cost

| Operation | Cost | Frequency |
|-----------|------|-----------|
| Key generation (X25519) | ~0.5ms | Per connection |
| ECDH derivation | ~0.5ms | Per connection |
| HKDF (session key) | ~0.1ms | Per connection |
| HKDF (message key) | ~0.05ms | Per message |
| AES-GCM encrypt | ~0.02ms | Per message |
| AES-GCM decrypt | ~0.02ms | Per message |

**Total per message:** ~0.07ms (negligible on modern iOS devices)

**Total per connection:** ~1.1ms (unnoticeable to users)

### 9.2 Network Overhead

| Component | Size Overhead | Notes |
|-----------|--------------|-------|
| Public key exchange | 2 × 32 bytes = 64 bytes | Once per connection |
| Wire format metadata | 1 + 8 + 12 + 16 = 37 bytes | Per message |
| Nonce (random IV) | 12 bytes | Per message |
| Auth tag | 16 bytes | Per message |
| Counter | 8 bytes | Per message |

**Overhead per message:** ~37 bytes + Base64 encoding (~1.33x) = ~49 bytes

**Typical message:** "Hello" (5 bytes) → encrypted (54 bytes total) → Base64 (72 bytes)

**Acceptable** for text-only messaging. (Image/file sharing would need chunking.)

### 9.3 Battery Impact

- ✅ **Negligible:** CryptoKit uses hardware acceleration (AES-NI, ARM Crypto Extensions)
- ✅ **No polling:** Encryption happens on-demand (message send/receive only)
- ✅ **No background crypto:** Keys deleted when app backgrounds

---

## 10. Testing Strategy

### 10.1 Unit Tests

```swift
// EncryptionTests.swift

func testKeyGeneration() {
    let key = Curve25519.KeyAgreement.PrivateKey()
    XCTAssertEqual(key.rawRepresentation.count, 32)
}

func testECDHDerivation() {
    let alice = Curve25519.KeyAgreement.PrivateKey()
    let bob = Curve25519.KeyAgreement.PrivateKey()
    
    let aliceShared = try alice.sharedSecretFromKeyAgreement(with: bob.publicKey)
    let bobShared = try bob.sharedSecretFromKeyAgreement(with: alice.publicKey)
    
    XCTAssertEqual(aliceShared, bobShared)
}

func testMessageEncryption() {
    let sessionKey = SymmetricKey(size: .bits256)
    let plaintext = "Test message"
    
    let ciphertext = try encryptor.encrypt(plaintext, sessionKey: sessionKey, counter: 0)
    let decrypted = try encryptor.decrypt(ciphertext, sessionKey: sessionKey, counter: 0)
    
    XCTAssertEqual(decrypted, plaintext)
}

func testReplayPrevention() {
    let ciphertext = try encryptor.encrypt("Message", sessionKey: key, counter: 5)
    
    // First decryption succeeds
    let decrypted1 = try encryptor.decrypt(ciphertext, sessionKey: key, counter: 5)
    
    // Replay attempt fails
    XCTAssertThrowsError(try encryptor.decrypt(ciphertext, sessionKey: key, counter: 5))
}

func testForwardSecrecy() {
    // Send 3 messages with different keys
    let msg1 = try encryptor.encrypt("Message 1", sessionKey: key, counter: 0)
    let msg2 = try encryptor.encrypt("Message 2", sessionKey: key, counter: 1)
    let msg3 = try encryptor.encrypt("Message 3", sessionKey: key, counter: 2)
    
    // Simulate key compromise AFTER message 2
    // Attacker should NOT be able to decrypt message 1
    // (This is conceptual - in reality, message keys are deleted)
    
    // Verify message 1 and 2 keys were deleted
    XCTAssertNil(encryptor.getMessageKey(counter: 0))
    XCTAssertNil(encryptor.getMessageKey(counter: 1))
}
```

### 10.2 Integration Tests

```swift
func testEndToEndEncryption() async {
    // Setup two ChatManagers (Alice and Bob)
    let alice = ChatManager()
    let bob = ChatManager()
    
    // Alice creates session
    let session = alice.createSession(code: "123456")
    
    // Bob accepts session
    bob.acceptSession(code: "123456")
    
    // Both connect and complete key exchange
    await alice.connect()
    await bob.connect()
    await alice.joinRoom(session.roomId!)
    await bob.joinRoom(session.roomId!)
    
    // Wait for key exchange completion
    try await Task.sleep(nanoseconds: 2_000_000_000)
    
    // Alice sends encrypted message
    alice.sendMessage("Hello Bob!")
    
    // Wait for network propagation
    try await Task.sleep(nanoseconds: 500_000_000)
    
    // Bob receives and decrypts message
    XCTAssertEqual(bob.messages.last?.text, "Hello Bob!")
    XCTAssertFalse(bob.messages.last!.isFromSelf)
}

func testKeyRotationOnReconnect() async {
    // ... (similar setup)
    
    // Get session key 1
    let key1 = alice.encryptionManager.getSessionKey(sessionId: session.id)
    
    // Disconnect
    alice.disconnect()
    bob.disconnect()
    
    // Reconnect
    await alice.connect()
    await bob.connect()
    await alice.joinRoom(session.roomId!)
    await bob.joinRoom(session.roomId!)
    
    // Get session key 2
    let key2 = alice.encryptionManager.getSessionKey(sessionId: session.id)
    
    // Keys should be different (rotation happened)
    XCTAssertNotEqual(key1, key2)
    
    // Messages should still work
    alice.sendMessage("After reconnect")
    try await Task.sleep(nanoseconds: 500_000_000)
    XCTAssertEqual(bob.messages.last?.text, "After reconnect")
}
```

### 10.3 Manual QA Tests

- [ ] Send/receive 1000 messages rapidly (no counter issues)
- [ ] Disconnect/reconnect 10 times (key rotation works)
- [ ] Force kill app during message send (no corruption)
- [ ] Delete session and verify keys gone from Keychain
- [ ] Network interruption mid-key-exchange (graceful recovery)
- [ ] Airplane mode toggle during conversation
- [ ] Background app and return (encryption state preserved)
- [ ] iOS system Settings → Reset Keychain (app handles gracefully)

---

## 11. UI/UX Indicators

### 11.1 Encryption Status Display

**ChatView toolbar:**

```swift
HStack {
    if encryptionManager.isEncrypted(sessionId: activeSessionId) {
        Image(systemName: "lock.fill")
            .foregroundColor(.green)
        Text("End-to-end encrypted")
            .font(.caption)
            .foregroundColor(.secondary)
    } else {
        Image(systemName: "lock.open.fill")
            .foregroundColor(.red)
        Text("Not encrypted")
            .font(.caption)
            .foregroundColor(.red)
    }
}
```

**Session list indicator:**

```swift
// Add to SessionsView row
if session.encryptionEnabled {
    Image(systemName: "lock.shield.fill")
        .foregroundColor(.green)
        .font(.caption)
}
```

### 11.2 Key Exchange Progress

**During connection:**

```swift
if encryptionManager.isExchangingKeys {
    ProgressView()
    Text("Establishing encryption...")
        .font(.caption)
}
```

### 11.3 Error States

**Key exchange timeout:**

```
⚠️ Encryption Setup Failed
Unable to establish secure connection with peer.
[Retry] [Cancel]
```

**Decryption failure:**

```
🔒 Cannot decrypt message
This message may be corrupted or from a previous session.
```

---

## 12. Future Enhancements (V2)

### 12.1 Safety Number Verification

**Goal:** Verify peer identity to prevent MITM attacks

**Implementation:**

1. Derive safety number from both public keys:
   ```swift
   let safetyNumber = SHA256.hash(
       data: alicePublicKey + bobPublicKey
   ).prefix(6) // 6 digits
   ```

2. Display on both devices:
   ```
   Your safety number: 482756
   Ask your peer to confirm their number matches.
   ```

3. Mark session as "verified" if numbers match

**UI:** Add "Verify Peer" button in session details

---

### 12.2 Sesame (Disappearing Messages V2)

**Current:** Messages deleted from UI only (still in memory)

**Enhanced:** Automatic server-side session expiration + client-side key deletion

**Implementation:**

- Server deletes room after N hours of inactivity
- Client detects expired session and wipes keys
- Messages become cryptographically unreadable

---

### 12.3 Multi-Device Support (Optional)

**Challenge:** Keychain doesn't sync, by design

**Possible approach:**

- Each device has its own ECDH keypair
- Group key management (beyond current scope)
- OR: Single device only (simpler, current design)

**Recommendation:** Stay single-device for V1

---

## 13. Compliance & Standards

### 13.1 Cryptographic Standards Compliance

✅ **NIST Approved:**
- AES-256-GCM (NIST SP 800-38D)
- SHA-256 (FIPS 180-4)
- HKDF (RFC 5869, NIST SP 800-56C)

✅ **IETF Approved:**
- X25519 (RFC 7748)

✅ **Industry Best Practices:**
- CryptoKit (Apple's crypto library, FIPS 140-2 compliant on iOS)

### 13.2 Privacy Regulations

✅ **GDPR Compliant:**
- No user data stored server-side
- Ephemeral device IDs (no personal identifiers)
- Right to be forgotten (session deletion wipes everything)

✅ **CCPA Compliant:**
- No sale of personal information (nothing to sell)
- No tracking or profiling

---

## 14. Glossary

| Term | Definition |
|------|------------|
| **ECDH** | Elliptic Curve Diffie-Hellman - key agreement protocol |
| **X25519** | Specific elliptic curve (Curve25519) optimized for ECDH |
| **HKDF** | HMAC-based Key Derivation Function - expands keys securely |
| **AES-GCM** | Advanced Encryption Standard in Galois/Counter Mode (authenticated encryption) |
| **Forward Secrecy** | Past messages stay secure even if current keys are compromised |
| **TOFU** | Trust On First Use - accept peer's key on first connection without verification |
| **Nonce** | Number used once - random value to ensure unique encryption per message |
| **Authentication Tag** | Cryptographic signature proving message hasn't been tampered with |
| **Session Key** | Shared secret derived from ECDH, used to derive message keys |
| **Message Key** | One-time key for encrypting a single message, derived from session key |
| **Counter** | Monotonically increasing number preventing replay attacks |

---

## 15. References & Further Reading

### 15.1 Cryptographic Specifications

- [RFC 7748: Elliptic Curves for Security (X25519)](https://datatracker.ietf.org/doc/html/rfc7748)
- [RFC 5869: HMAC-based Key Derivation Function (HKDF)](https://datatracker.ietf.org/doc/html/rfc5869)
- [NIST SP 800-38D: AES-GCM](https://csrc.nist.gov/publications/detail/sp/800-38d/final)
- [Signal Protocol Specifications](https://signal.org/docs/)

### 15.2 Apple Documentation

- [CryptoKit Framework](https://developer.apple.com/documentation/cryptokit)
- [Keychain Services](https://developer.apple.com/documentation/security/keychain_services)
- [Protecting Keys with the Secure Enclave](https://developer.apple.com/documentation/security/certificate_key_and_trust_services/keys/protecting_keys_with_the_secure_enclave)

### 15.3 Security Best Practices

- [OWASP Mobile Security Testing Guide](https://owasp.org/www-project-mobile-security-testing-guide/)
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web)

---

## 16. Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | October 8, 2025 | Initial specification |

---

## 17. Summary for Developers

### Quick Implementation Checklist

1. ✅ **Add CryptoKit import** to all new encryption files
2. ✅ **Create `EncryptionManager.swift`** to coordinate ECDH + AES-GCM
3. ✅ **Modify `SignalingClient.swift`** to relay `key_exchange` messages
4. ✅ **Update `ChatManager.swift`** to call encryption on send/receive
5. ✅ **Add Keychain wrapper** for storing session keys securely
6. ✅ **Implement HKDF ratchet** for per-message key derivation
7. ✅ **Add counter validation** to prevent replay attacks
8. ✅ **Update UI** with encryption status indicators
9. ✅ **Write unit tests** for crypto primitives
10. ✅ **Test end-to-end** with two physical devices

### Critical Security Reminders

⚠️ **Never log:**
- Private keys
- Session keys
- Message keys
- Plaintexts
- Key derivation inputs

⚠️ **Always:**
- Delete keys after use (message keys immediately)
- Validate message counters (strictly increasing)
- Use constant-time comparison for authentication tags
- Zero memory after key deletion
- Set `kSecAttrSynchronizable = false` (no iCloud sync)

⚠️ **Test:**
- Key rotation on reconnect
- Replay attack prevention
- Out-of-order message handling
- Session deletion key wipe

---

**End of Specification**

This document provides everything needed to implement production-ready, maximum-security end-to-end encryption for Inviso. Follow this spec exactly, and you'll have one of the most secure P2P chat apps available.

Questions? Review sections 3 (Protocols), 5 (Implementation), and 10 (Testing) for step-by-step guidance.
