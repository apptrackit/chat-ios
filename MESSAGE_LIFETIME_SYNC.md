# Message Lifetime Synchronization Protocol

**Version:** 1.0  
**Status:** ✅ Production Ready  
**Last Updated:** October 26, 2025

---

## Overview

Inviso allows two peers to **negotiate** how long messages should be stored. Both devices must agree on the retention policy before messages are saved to disk.

### Key Principles

1. **Mutual Agreement Required** - Both peers must accept the lifetime setting
2. **Server-Agnostic** - Negotiation happens peer-to-peer via signaling
3. **No Default Persistence** - If no agreement, default to ephemeral (RAM only)
4. **Real-time Sync** - Policy changes are communicated immediately
5. **UI Transparency** - Users always see the current retention policy

---

## Message Lifetime Options

| Option | Duration | Icon | Description |
|--------|----------|------|-------------|
| **Delete on Leave** | Session only | `eye.slash` | Messages never saved to disk (RAM only) |
| **1 Hour** | 3,600 sec | `clock` | Saved to disk, auto-deleted 1 hour after send time |
| **6 Hours** | 21,600 sec | `clock` | Saved to disk, auto-deleted 6 hours after send time |
| **1 Day** | 86,400 sec | `sun.max` | Saved to disk, auto-deleted 1 day after send time |
| **7 Days** | 604,800 sec | `calendar` | Saved to disk, auto-deleted 7 days after send time |
| **30 Days** | 2,592,000 sec | `calendar.badge.clock` | Saved to disk, auto-deleted 30 days after send time |

### Lifetime Change Behavior

**Important:** When you change the retention mode, it only affects **new messages**. Existing messages keep their original expiration times.

**Example:**
1. Mode: "30 Days" → Send "Hello" → Expires in 30 days
2. Mode: "1 Day" → Send "World" → Expires in 1 day  
3. Mode: "Ephemeral" → Send "Test" → Never saved

**Result after leaving chat:**
- "Hello" remains stored and expires in 30 days (original)
- "World" remains stored and expires in 1 day (original)
- "Test" was never saved (ephemeral)

This ensures users don't lose data when experimenting with different retention policies.

---

## Synchronization Protocol

### State Machine

Each session has a lifetime negotiation state:

```
┌──────────────┐
│  No Policy   │  (Initial state - ephemeral)
└──────┬───────┘
       │ User proposes
       ↓
┌──────────────┐
│  Pending     │  (Waiting for peer response)
└──────┬───────┘
       │ Peer accepts
       ↓
┌──────────────┐
│  Agreed      │  (Both confirmed - messages saved)
└──────────────┘
```

### Message Flow

#### 1. Propose Lifetime

**Trigger:** User changes retention setting in UI

```
Client A                    Signaling Server              Client B
   │                               │                          │
   │ 1. User selects "1 Day"       │                          │
   ├─────────────────────────────→ │                          │
   │ lifetime_proposal             │                          │
   │ {                             │                          │
   │   type: "lifetime_proposal",  │                          │
   │   sessionId: "abc123...",     │                          │
   │   lifetime: "1d",             │                          │
   │   proposedAt: 1698345600.0    │                          │
   │ }                             │                          │
   │                               ├─────────────────────────→│
   │                               │ Forward to peer          │
   │                               │                          │
   │                               │     2. Peer receives     │
   │                               │     Shows notification   │
   │                               │     "Accept 1 Day?"      │
```

#### 2. Accept Proposal

**Trigger:** Peer accepts the proposed lifetime

```
Client A                    Signaling Server              Client B
   │                               │                          │
   │                               │                          │
   │                               │  3. User clicks "Accept" │
   │                               │ ←─────────────────────────┤
   │                               │ lifetime_accept          │
   │                               │ {                        │
   │                               │   type: "lifetime_accept",│
   │                               │   sessionId: "abc123...", │
   │                               │   lifetime: "1d",        │
   │                               │   acceptedAt: 1698345605.0│
   │                               │ }                        │
   │ ←─────────────────────────────┤                          │
   │ 4. Both mark as agreed        │                          │
   │ ✅ Messages now saved          │                          │
   │                               │      ✅ Messages saved    │
   │                               │                          │
   │ 5. System message displayed   │                          │
   │ "Messages will be deleted     │                          │
   │  after 1 Day"                 │                          │
```

#### 3. Reject Proposal

**Trigger:** Peer declines the proposed lifetime

```
Client A                    Signaling Server              Client B
   │                               │                          │
   │                               │                          │
   │                               │  3. User clicks "Reject" │
   │                               │ ←─────────────────────────┤
   │                               │ lifetime_reject          │
   │                               │ {                        │
   │                               │   type: "lifetime_reject",│
   │                               │   sessionId: "abc123...", │
   │                               │   reason: "too long"     │
   │                               │ }                        │
   │ ←─────────────────────────────┤                          │
   │ 4. Reset to ephemeral         │                          │
   │ ⚠️ Messages NOT saved          │                          │
   │                               │      ⚠️ Stays ephemeral   │
```

---

## Signaling Message Format

### lifetime_proposal

Sent when a user wants to change the retention policy.

```json
{
  "type": "lifetime_proposal",
  "sessionId": "abc123-def456-...",
  "lifetime": "1d",
  "proposedAt": 1698345600.0
}
```

**Fields:**
- `type`: Always "lifetime_proposal"
- `sessionId`: Room/session identifier
- `lifetime`: One of: "ephemeral", "1h", "6h", "1d", "7d", "30d"
- `proposedAt`: Unix timestamp when proposed

### lifetime_accept

Sent when a peer accepts the proposed lifetime.

```json
{
  "type": "lifetime_accept",
  "sessionId": "abc123-def456-...",
  "lifetime": "1d",
  "acceptedAt": 1698345605.0
}
```

**Fields:**
- `type`: Always "lifetime_accept"
- `sessionId`: Room/session identifier
- `lifetime`: Must match the proposed lifetime
- `acceptedAt`: Unix timestamp when accepted

### lifetime_reject

Sent when a peer rejects the proposed lifetime.

```json
{
  "type": "lifetime_reject",
  "sessionId": "abc123-def456-...",
  "reason": "too long"
}
```

**Fields:**
- `type`: Always "lifetime_reject"
- `sessionId`: Room/session identifier
- `reason`: Optional explanation (not shown to user)

---

## Conflict Resolution

### Scenario 1: Simultaneous Proposals

**Problem:** Both peers propose different lifetimes at the same time.

```
Client A proposes "1 Day" ────────┐
                                  ├──→ CONFLICT
Client B proposes "7 Days" ───────┘
```

**Resolution:** Last proposal wins (most recent `proposedAt` timestamp).

```swift
func handleSimultaneousProposals(
    myProposal: LifetimeProposal,
    peerProposal: LifetimeProposal
) -> LifetimeProposal {
    // Keep the most recent proposal
    if peerProposal.proposedAt > myProposal.proposedAt {
        // Peer's proposal is newer - accept it
        return peerProposal
    } else {
        // My proposal is newer - wait for peer to accept
        return myProposal
    }
}
```

### Scenario 2: Proposal During Active Agreement

**Problem:** User changes lifetime while an agreement already exists.

**Resolution:** Requires new negotiation. Old agreement remains until new one is accepted. **Existing messages keep their original expiration times.**

```
Current: "1 Day" (agreed)
   ↓
User proposes "7 Days"
   ↓
Pending until peer accepts
   ↓
If accepted: 
   - New mode: "7 Days" (for future messages)
   - Old messages: Still expire after their original "1 Day"
If rejected: 
   - Stay at "1 Day" (for future messages)
   - Old messages: Still expire after their original "1 Day"
```

**Key point:** Mode changes only affect messages sent **after** the new agreement, not existing messages.

### Scenario 3: Disconnection During Negotiation

**Problem:** Connection lost while waiting for peer response.

**Resolution:** Reset to ephemeral on reconnection (requires new negotiation).

```
Pending proposal → Disconnect → Reconnect → Ephemeral
```

---

## UI Behavior

### Indicator Display

Messages should show the current retention policy:

```
┌─────────────────────────────────────┐
│ Chat with Alice                     │
├─────────────────────────────────────┤
│ [🔒] Messages: Delete after 1 Day   │  ← Status bar
├─────────────────────────────────────┤
│ Alice: Hey there!                   │
│ You: Hi!                            │
│ ...                                 │
└─────────────────────────────────────┘
```

### System Messages

Show system messages when lifetime changes:

```
┌─────────────────────────────────────┐
│ [System] Messages will be deleted   │
│          after 1 Day (agreed by both)│
├─────────────────────────────────────┤
│ Alice: Great!                       │
│ You: Perfect                        │
└─────────────────────────────────────┘
```

### Settings Screen (Only When Connected)

```
┌─────────────────────────────────────┐
│ Message Retention                   │
├─────────────────────────────────────┤
│ ○ Delete on Leave (Ephemeral)       │
│ ○ 1 Hour                            │
│ ● 1 Day                  [Current]  │
│ ○ 7 Days                            │
│ ○ 30 Days                           │
├─────────────────────────────────────┤
│ [Propose to Peer]                   │
└─────────────────────────────────────┘
```

**Note:** This setting is **disabled when not connected** (greyed out).

### Notification Prompt

When peer proposes a lifetime change:

```
┌─────────────────────────────────────┐
│ Lifetime Change Request             │
├─────────────────────────────────────┤
│ Alice wants to change message       │
│ retention to:                       │
│                                     │
│         🗓️ 7 Days                   │
│                                     │
│ Messages will auto-delete after     │
│ this time.                          │
├─────────────────────────────────────┤
│ [Reject]              [Accept]      │
└─────────────────────────────────────┘
```

---

## Implementation Example

### Proposing a Lifetime

```swift
func proposeLifetime(_ lifetime: MessageLifetime) {
    guard isP2PConnected else {
        print("⚠️ Cannot propose while disconnected")
        return
    }
    
    // Update local state
    var session = activeSession
    session.messageLifetime = lifetime
    session.lifetimeAgreedByBoth = false
    
    // Send proposal to peer via signaling
    let proposal = LifetimeProposalMessage(
        sessionId: roomId,
        lifetime: lifetime.rawValue,
        proposedAt: Date().timeIntervalSince1970
    )
    
    signaling.send(proposal)
    
    // Show system message
    let systemMsg = ChatMessage(
        text: "Proposed: Messages delete after \(lifetime.displayName)",
        timestamp: Date(),
        isFromSelf: false,
        isSystem: true
    )
    messages.append(systemMsg)
    
    print("📤 Proposed lifetime: \(lifetime.displayName)")
}
```

### Receiving a Proposal

```swift
func handleLifetimeProposal(_ proposal: LifetimeProposalMessage) {
    guard let lifetime = MessageLifetime(rawValue: proposal.lifetime) else {
        print("⚠️ Invalid lifetime value")
        return
    }
    
    // Show notification to user
    showLifetimeProposalAlert(
        lifetime: lifetime,
        onAccept: {
            // Send acceptance
            let accept = LifetimeAcceptMessage(
                sessionId: proposal.sessionId,
                lifetime: proposal.lifetime,
                acceptedAt: Date().timeIntervalSince1970
            )
            self.signaling.send(accept)
            
            // Update local session
            self.activeSession.messageLifetime = lifetime
            self.activeSession.lifetimeAgreedAt = Date()
            self.activeSession.lifetimeAgreedByBoth = true
            
            // Show system message
            let systemMsg = ChatMessage(
                text: "Messages will be deleted after \(lifetime.displayName)",
                timestamp: Date(),
                isFromSelf: false,
                isSystem: true
            )
            self.messages.append(systemMsg)
            
            print("✅ Accepted lifetime: \(lifetime.displayName)")
        },
        onReject: {
            // Send rejection
            let reject = LifetimeRejectMessage(
                sessionId: proposal.sessionId,
                reason: "user_declined"
            )
            self.signaling.send(reject)
            
            print("❌ Rejected lifetime proposal")
        }
    )
}
```

### Handling Acceptance

```swift
func handleLifetimeAccept(_ accept: LifetimeAcceptMessage) {
    guard let lifetime = MessageLifetime(rawValue: accept.lifetime) else {
        print("⚠️ Invalid lifetime value")
        return
    }
    
    // Update local session
    activeSession.messageLifetime = lifetime
    activeSession.lifetimeAgreedAt = Date(timeIntervalSince1970: accept.acceptedAt)
    activeSession.lifetimeAgreedByBoth = true
    
    // Show system message
    let systemMsg = ChatMessage(
        text: "Messages will be deleted after \(lifetime.displayName)",
        timestamp: Date(),
        isFromSelf: false,
        isSystem: true
    )
    messages.append(systemMsg)
    
    print("✅ Peer accepted lifetime: \(lifetime.displayName)")
}
```

---

## Storage Integration

Once lifetime is agreed, messages are saved with expiration:

```swift
func sendMessage(_ text: String) {
    // ... existing encryption code ...
    
    // Save to disk if lifetime is not ephemeral
    if let config = getStorageConfig(for: sessionId),
       config.lifetime != .ephemeral,
       config.agreedByBoth {
        
        do {
            try MessageStorageManager.shared.saveMessage(
                message,
                sessionId: sessionId,
                config: config
            )
            
            // Mark as saved
            message.savedLocally = true
            message.lifetime = config.lifetime
            message.expiresAt = message.timestamp.addingTimeInterval(
                config.lifetime.seconds ?? 0
            )
            
            print("✅ Message saved with \(config.lifetime.displayName) expiration")
        } catch {
            print("❌ Failed to save message: \(error)")
        }
    }
}
```

---

## Edge Cases

### Case 1: Connection Lost During Save

**Problem:** Message sent and encrypted, but connection drops before peer receives it.

**Solution:** Keep message in outbox, retry when reconnected.

```swift
struct OutboxMessage {
    let message: ChatMessage
    let retryCount: Int
    let maxRetries: Int = 3
}

var outbox: [OutboxMessage] = []
```

### Case 2: Time Skew Between Devices

**Problem:** Devices have different system clocks, causing wrong expiration times.

**Solution:** Use relative durations calculated at send time, not absolute timestamps.

```swift
// ❌ Wrong: Absolute timestamp (depends on sender's clock)
expiresAt = Date(timeIntervalSince1970: 1698349200.0)

// ✅ Correct: Relative duration from message timestamp
expiresAt = message.timestamp.addingTimeInterval(lifetime.seconds)
```

### Case 3: Storage Locked When Message Arrives

**Problem:** Message arrives but storage is locked (user hasn't unlocked with passphrase).

**Solution:** Keep message in RAM until storage is unlocked, then save retroactively with correct expiration.

```swift
var pendingMessages: [ChatMessage] = []

func unlockStorage() {
    // ... unlock code ...
    
    // Save pending messages with their original timestamps
    for message in pendingMessages {
        // Expiration calculated from original send time, not now
        try? saveMessage(message)
    }
    pendingMessages.removeAll()
}
```

### Case 4: Mode Changed While Messages in Transit

**Problem:** User changes mode from "30 Days" to "Ephemeral" while peer is sending messages with "30 Days" metadata.

**Solution:** Receiving device saves messages with the expiration time embedded in the message, not the current mode.

```swift
// Each message carries its own expiration metadata
struct ChatMessage {
    let timestamp: Date
    let expiresAt: Date?  // Set by sender at send time
    // Current mode doesn't affect this message
}
```

---

## Testing Scenarios

### Test 1: Basic Proposal & Accept

```
1. Client A proposes "1 Day"
2. Client B receives proposal
3. Client B accepts
4. Both show "Messages delete after 1 Day"
5. Send message - verify saved on both devices
6. Check file has correct expiresAt timestamp
```

### Test 2: Proposal & Reject

```
1. Client A proposes "7 Days"
2. Client B rejects
3. Both show "Delete on Leave (Ephemeral)"
4. Send message - verify NOT saved to disk
5. Leave chat - verify message gone from RAM
```

### Test 3: Change During Active Agreement

```
1. Both agree on "1 Day"
2. Client A proposes "7 Days"
3. Client B accepts
4. System message: "Changed to 7 Days"
5. Old messages keep "1 Day" expiration
6. New messages get "7 Days" expiration
```

### Test 4: Reconnection Resets

```
1. Both agree on "1 Day"
2. Client B disconnects
3. Client A sends message (saved with 1 Day)
4. Client B reconnects
5. Lifetime reset to "Ephemeral"
6. Must renegotiate before saving new messages
```

---

## Security Considerations

### Privacy

- **No server knowledge:** Server never sees lifetime proposals (end-to-end encrypted signaling)
- **No metadata leak:** Lifetime setting is not stored on server
- **User control:** Both users must explicitly consent to any retention

### Attack Vectors

| Attack | Mitigation |
|--------|-----------|
| **Peer lies about deletion** | Trust model (can't verify peer's local storage) |
| **MITM changes proposal** | Signed with E2EE keys (future enhancement) |
| **Malicious peer floods proposals** | Rate limit + UI throttling |

---

## Future Enhancements

1. **Signed Proposals:** Use E2EE session key to sign lifetime messages
2. **Partial Lifetime:** Different lifetimes for text vs media
3. **Conditional Deletion:** Delete if not opened within X time
4. **Proof of Deletion:** Cryptographic proof that peer deleted messages

---

**Last Updated:** October 26, 2025  
**Maintained By:** Inviso Protocol Team
