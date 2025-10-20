# Message Retention (Ephemeral Storage)

This document explains the new message retention feature added to Inviso. Privacy is the top priority: messages remain ephemeral by default, and all retention configuration is exchanged only between peers over the established E2EE DataChannel.

## Goals

- Allow users to choose how long messages are stored locally: No Storage (ephemeral), 1 hour, 24 hours, or 1 week.
- Ensure both peers agree on policy by syncing the choice over the E2EE channel.
- Keep message content private: policies are sent as encrypted control messages; message content never leaves the P2P encrypted channel.
- Provide a local, encrypted-only storage mechanism for messages when retention is enabled.
- Allow deleting all stored messages per-session.

## How it works (overview)

- Local model:
  - `ChatMessage` now has `expiresAt: Date?` indicating when the message should be considered expired.
  - New `MessageRetentionPolicy` enum represents the available options.

- Storage:
  - `MessageStorage` writes per-session message JSON files into `Application Support/Messages/`.
  - Files are written atomically and protected with `.completeFileProtection`.
  - Messages saved to disk respect the `expiresAt` field. On load, expired messages are filtered out.
  - A storage-wide cleanup routine removes expired messages periodically.

- Syncing policies:
  - When a user changes the retention policy in `RoomSettingsView`, `ChatManager.updateRetentionPolicy(_:)` is called.
  - This sets the local `currentRetentionPolicy`, recalculates expiration timestamps for existing messages, and sends a `RetentionPolicyMessage` to the peer via the encrypted DataChannel.
  - The peer sets `peerRetentionPolicy` when it receives the policy sync message.

- Default behavior:
  - Default policy is `noStorage` (original ephemeral behavior).
  - If `noStorage` is selected, stored message files for the session are deleted immediately.
  - If a storage policy is selected, new messages will receive an `expiresAt` timestamp calculated from the current time + policy duration.

## Privacy & Security notes

- Policy synchronization is performed only over the established E2EE DataChannel. The server is not involved and never sees message content or policy messages.
- Messages stored on disk are saved as JSON within the app sandbox and protected with Apple's file protection; they are not uploaded or synced off-device.
- Changing to `noStorage` proactively deletes stored messages for the session.
- Erase All Data (`AppDataReset`) now also erases message files.

## Implementation notes for developers

- Models:
  - `ChatMessage` (now Codable) includes `expiresAt: Date?` and `isExpired` helper.
  - `MessageRetentionPolicy` supports `durationSeconds` and `expirationDate(from:)` helpers.
  - `RetentionPolicyMessage` is a small Codable control message used to sync the policy.

- Key files changed:
  - `Inviso/Models/ChatModels.swift` — models updated/added.
  - `Inviso/Services/Storage/MessageStorage.swift` — new storage service.
  - `Inviso/Chat/ChatManager.swift` — retention logic, saving/loading, policy sync, cleanup timer.
  - `Inviso/Views/Sessions/RoomSettingsView.swift` — UI picker and delete button.

## Edge cases and decisions

- This implementation uses the device's clock to compute `expiresAt`. A server-authoritative timestamp could be used instead (to avoid clock skew) but would require sending the policy through the server or requesting a server timestamp. By design we avoid server involvement to keep policy negotiation P2P and private.
- If one peer sets a policy and the other peer later sets a conflicting policy, both clients will know each other's preference (via `peerRetentionPolicy`). The app currently honors the local policy for local storage; you may implement a conflict resolution (e.g., use the stricter/shorter retention) if desired.

## Next steps / improvements

- Implement optional server timestamp negotiation for expiry calculation if a server-trusted clock is desired.
- Provide UI feedback when peer policy differs from local policy and offer an agreed-upon resolution.
- Add unit tests for `MessageStorage`, message cleanup, and policy sync.

