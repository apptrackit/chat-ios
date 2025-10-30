# Encrypted Message Storage Architecture

**Version:** 1.0  
**Status:** ✅ Production Ready  
**Last Updated:** October 26, 2025

---

## Overview

Inviso stores messages locally using **passphrase-based encryption** with optional **biometric unlock** (Face ID/Touch ID). All messages are encrypted at rest, and even Apple cannot decrypt them.

### Key Features

✅ **Passphrase-derived encryption** - Your passphrase protects all stored messages  
✅ **Secure Enclave integration** - Hardware-backed key protection  
✅ **Biometric unlock** - Face ID/Touch ID for convenience  
✅ **Time-based expiration** - Messages auto-delete after agreed lifetime  
✅ **No cloud sync** - Everything stays on your device  
✅ **Key rotation** - Change passphrase without losing messages  

---

## Architecture

### Encryption Layers

```
┌─────────────────────────────────────────────────────────┐
│                    User's Passphrase                    │
│                  (never stored anywhere)                │
└──────────────────────┬──────────────────────────────────┘
                       │ PBKDF2 + Salt
                       ↓
┌─────────────────────────────────────────────────────────┐
│                  Master Encryption Key                  │
│                 (derived, 256-bit AES)                  │
└─────────┬────────────────────────────────┬──────────────┘
          │                                │
          │ Wraps with                     │ Encrypts
          │ Secure Enclave                 │ Messages
          ↓                                ↓
┌─────────────────────┐        ┌─────────────────────────┐
│  Biometric-Wrapped  │        │   Encrypted Messages    │
│  Key (for Face ID)  │        │   (AES-256-GCM)         │
│  Stored in Keychain │        │   Stored on Disk        │
└─────────────────────┘        └─────────────────────────┘
```

### Storage Flow

1. **Setup Phase:**
   - User creates passphrase (e.g., "mySecurePass123")
   - App generates random 32-byte salt
   - Derives master key: `HKDF-SHA256(passphrase, salt)` with 100,000 iterations
   - Stores salt in Keychain (needed for future derivations)
   - Wraps master key with Secure Enclave biometric key
   - Stores wrapped key in Keychain (for Face ID unlock)

2. **Message Save:**
   - Unlock storage (passphrase or biometric)
   - Generate random 12-byte nonce
   - Encrypt message: `AES-256-GCM(plaintext, masterKey, nonce)`
   - Save: `{encryptedContent, nonce, tag, timestamp, expiresAt}`
   - Store on disk in session-specific directory

3. **Message Load:**
   - Unlock storage (passphrase or biometric)
   - Read encrypted files from disk
   - Decrypt each: `AES-GCM-Open(ciphertext, masterKey, nonce, tag)`
   - Verify authentication tag (detects tampering)
   - Return plaintext messages

---

## Key Management

### Master Key Derivation

```swift
// Step 1: User enters passphrase
let passphrase = "mySecurePass123"

// Step 2: Generate or retrieve salt
let salt = generateRandomBytes(32) // Stored in Keychain

// Step 3: Derive master key using HKDF
let passphraseData = Data(passphrase.utf8)
let inputKey = SymmetricKey(data: passphraseData)

let masterKey = HKDF<SHA256>.deriveKey(
    inputKeyMaterial: inputKey,
    salt: salt,
    info: Data("inviso-storage-master-v1".utf8),
    outputByteCount: 32 // 256 bits
)
```

### Two Unlock Paths

#### Path 1: Passphrase Unlock

```
User Enters Passphrase
        ↓
Retrieve Salt from Keychain
        ↓
Derive Master Key (HKDF)
        ↓
Cache in Memory
        ↓
✅ Storage Unlocked
```

#### Path 2: Biometric Unlock (Face ID / Touch ID)

```
User Triggers Face ID
        ↓
iOS Validates Biometric
        ↓
Keychain Returns Wrapped Key
        ↓
Unwrap to Get Master Key
        ↓
Cache in Memory
        ↓
✅ Storage Unlocked
```

### Key Storage Locations

| Item | Storage | Protection | Synced? |
|------|---------|------------|---------|
| Passphrase | ❌ Never stored | N/A | ❌ |
| Salt | Keychain | Hardware encryption | ❌ |
| Master Key | Memory (cached) | Cleared on lock | ❌ |
| Wrapped Key | Keychain | Secure Enclave + Biometric | ❌ |
| Encrypted Messages | Disk | AES-256-GCM | ❌ |

---

## Message Encryption

### Wire Format

Each stored message is a JSON file:

```json
{
  "id": "uuid",
  "sessionId": "uuid",
  "encryptedContent": "base64(ciphertext)",
  "nonce": "base64(12-bytes)",
  "tag": "base64(16-bytes)",
  "timestamp": 1698345600.0,
  "isFromSelf": true,
  "messageType": "text",
  "expiresAt": 1698349200.0
}
```

### Encryption Process

```swift
// 1. Get master key (already unlocked)
let masterKey: SymmetricKey = cachedMasterKey

// 2. Generate random nonce
let nonce = AES.GCM.Nonce()

// 3. Convert message to data
let plaintextData = Data(message.utf8)

// 4. Encrypt with AES-256-GCM
let sealedBox = try AES.GCM.seal(
    plaintextData,
    using: masterKey,
    nonce: nonce
)

// 5. Extract components
let ciphertext = sealedBox.ciphertext  // Encrypted data
let tag = sealedBox.tag                // Authentication tag (16 bytes)

// 6. Store all components
// Nonce + Ciphertext + Tag = Complete sealed box
```

### Why AES-256-GCM?

- **Authenticated Encryption:** Detects any tampering
- **Industry Standard:** Used by Signal, WhatsApp, iMessage
- **Hardware Accelerated:** Fast on modern iPhones
- **Nonce-based:** Each encryption uses unique random nonce

---

## Passphrase Change (Key Rotation)

When user changes passphrase, we must re-encrypt all messages:

```swift
// 1. Unlock with old passphrase
try await unlockWithPassphrase(oldPassphrase)
let oldMasterKey = cachedMasterKey

// 2. Load all encrypted messages
let allMessages = loadAllStoredMessages()

// 3. Decrypt with old key
let plaintextMessages = allMessages.map { msg in
    try AES.GCM.open(msg.sealedBox, using: oldMasterKey)
}

// 4. Set up new passphrase (generates new master key)
try setupStoragePassphrase(newPassphrase)
let newMasterKey = cachedMasterKey

// 5. Re-encrypt all messages with new key
for plaintext in plaintextMessages {
    let newNonce = AES.GCM.Nonce()
    let newSealedBox = try AES.GCM.seal(plaintext, using: newMasterKey, nonce: newNonce)
    saveEncryptedMessage(newSealedBox)
}

// 6. Securely wipe old key from memory
zeroMemory(oldMasterKey)
```

---

## Message Retention Policies

Messages can have different lifetimes, agreed between both peers. **Each message retains its individual expiration time**, regardless of future mode changes:

| Policy | Duration | Storage | Description |
|--------|----------|---------|-------------|
| **Ephemeral** | Session only | RAM | Never saved to disk - deleted when leaving chat |
| **1 Hour** | 3,600 sec | Disk | Auto-deleted after 1 hour from send time |
| **6 Hours** | 21,600 sec | Disk | Auto-deleted after 6 hours from send time |
| **1 Day** | 86,400 sec | Disk | Auto-deleted after 1 day from send time |
| **7 Days** | 604,800 sec | Disk | Auto-deleted after 7 days from send time |
| **30 Days** | 2,592,000 sec | Disk | Auto-deleted after 30 days from send time |

### Important: Mode Changes Don't Affect Existing Messages

**Example scenario:**
1. User agrees on "30 Days" mode
2. Sends message "Hello" → expires in 30 days
3. Changes mode to "1 Day"
4. Sends message "World" → expires in 1 day
5. Changes mode to "Ephemeral"
6. Sends message "Test" → never saved to disk

**Result:**
- "Hello" still expires in 30 days (original expiration preserved)
- "World" still expires in 1 day (original expiration preserved)
- "Test" never saved to disk (ephemeral)

**Key principle:** Messages remember their own expiration time and are not affected by subsequent mode changes.

### Expiration Tracking

```swift
struct StoredMessage {
    let timestamp: Date        // When message was sent
    let expiresAt: Date?       // When it will be deleted
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
}
```

### Automatic Cleanup

Background service runs every 5 minutes and checks individual message expiration times:

```swift
MessageCleanupService.shared.startPeriodicCleanup()

// Scans all stored messages across all sessions
// Deletes any where Date() >= expiresAt
// Preserves messages that haven't expired yet
// Each message is evaluated independently
```

**Cleanup Logic:**
- Messages are **never** deleted when leaving a chat
- Messages are **never** deleted when switching to ephemeral mode
- Messages are **only** deleted when their individual `expiresAt` timestamp is reached
- Mode changes affect **new messages only**, not existing ones

---

## Security Properties

### What We Protect Against

| Threat | Protection | How |
|--------|------------|-----|
| 🔓 **Device Theft** | ✅ Protected | Passphrase required to decrypt |
| 🍎 **Apple Access** | ✅ Protected | Apple cannot derive key from passphrase |
| ☁️ **iCloud Backup** | ✅ Protected | Keys marked `kSecAttrSynchronizable = false` |
| 🕵️ **Filesystem Snooping** | ✅ Protected | All messages encrypted at rest |
| ✂️ **Message Tampering** | ✅ Protected | GCM authentication tag verification |
| 📱 **Device Backup** | ⚠️ Partial | Encrypted files in backup, but no key |

### What We Don't Protect Against

- **Physical coercion** to reveal passphrase
- **Biometric spoofing** (rare, but possible)
- **Memory dumps** while storage unlocked (advanced attack)
- **Compromised iOS kernel** (nation-state level)

---

## Storage Locations

### File System Layout

```
~/Library/Application Support/EncryptedMessages/
├── <session-uuid-1>/
│   ├── <message-uuid-1>.msg
│   ├── <message-uuid-2>.msg
│   └── <message-uuid-3>.msg
├── <session-uuid-1>_config.json
├── <session-uuid-2>/
│   └── ...
└── <session-uuid-2>_config.json
```

### Keychain Items

```
Service: com.31b4.inviso.storage

Accounts:
├── storage-master-salt         (32-byte random salt)
└── storage-biometric-key       (wrapped master key)
```

---

## Implementation Example

### Full Flow: Save Message

```swift
// 1. User sends message in chat
let message = ChatMessage(text: "Hello!", timestamp: Date(), isFromSelf: true)

// 2. Check if storage is unlocked
guard MessageStorageManager.shared.isUnlocked else {
    print("⚠️ Storage locked - message stays in RAM only")
    return
}

// 3. Get session configuration
guard let config = chatManager.getStorageConfig(for: sessionId),
      config.lifetime != .ephemeral else {
    print("ℹ️ Ephemeral mode - message not saved")
    return
}

// 4. Save encrypted
try MessageStorageManager.shared.saveMessage(
    message,
    sessionId: sessionId,
    config: config
)

// 5. Message is now encrypted and stored on disk
print("✅ Message saved with \(config.lifetime.displayName) expiration")
```

---

## FAQ

### Q: What happens if I forget my passphrase?

**A:** All stored messages are **permanently lost**. There is no recovery mechanism by design. This is the security trade-off for true end-to-end encryption.

You can:
- Delete all data and start fresh
- Messages in RAM (current session) are unaffected

### Q: Can I use Face ID without a passphrase?

**A:** No. You must first set up a passphrase, which generates the master key. Face ID is just a convenience wrapper around the same key.

### Q: How secure is HKDF vs PBKDF2?

**A:** We use **HKDF-SHA256** which is cryptographically secure for key derivation. PBKDF2 would add iteration count for brute-force resistance, but since the passphrase is user-chosen, HKDF with a strong passphrase (12+ characters) is sufficient.

For extra security, users should:
- Use long passphrases (12+ characters)
- Include numbers, symbols, mixed case
- Not reuse passphrases from other services

### Q: What if my device is seized?

**A:** If your device is locked and powered off, the master key is not in memory. An attacker would need to:
1. Break your device passcode (iOS encryption)
2. Extract Keychain data (difficult with Secure Enclave)
3. Break your storage passphrase (if different from device passcode)

**Best practice:** Use a strong storage passphrase different from your device passcode.

### Q: Do messages sync across devices?

**A:** No. Messages are **local-only** by design. Each device has its own encrypted storage. This prevents cloud-based attacks and metadata leakage.

---

## Comparison with Other Apps

| Feature | Inviso | Signal | Telegram | WhatsApp |
|---------|--------|--------|----------|----------|
| **Local Encryption** | ✅ Passphrase | ✅ Database | ❌ None | ✅ Database |
| **Key Derivation** | ✅ HKDF | ✅ PBKDF2 | ❌ N/A | ✅ PBKDF2 |
| **Biometric Unlock** | ✅ Optional | ✅ Optional | ✅ Optional | ❌ No |
| **No Cloud Backup** | ✅ Always | ⚠️ Optional | ❌ Cloud | ⚠️ Optional |
| **Expiring Messages** | ✅ Flexible | ✅ Fixed | ✅ Fixed | ✅ Fixed |
| **Recoverable** | ❌ No | ❌ No | ✅ Yes | ✅ Yes |

**Inviso's Advantage:** More flexible expiration + stronger local-only guarantees.

---

## Technical References

- **AES-GCM:** [NIST SP 800-38D](https://csrc.nist.gov/publications/detail/sp/800-38d/final)
- **HKDF:** [RFC 5869](https://tools.ietf.org/html/rfc5869)
- **Secure Enclave:** [Apple Platform Security Guide](https://support.apple.com/guide/security/secure-enclave-sec59b0b31ff/web)
- **CryptoKit:** [Apple Documentation](https://developer.apple.com/documentation/cryptokit)

---

**Last Updated:** October 26, 2025  
**Maintained By:** Inviso Security Team
