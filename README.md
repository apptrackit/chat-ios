<div align="center">

# Inviso (chat-ios)

Peer‑to‑peer (P2P) ephemeral chat over WebRTC DataChannels for iOS (Swift / SwiftUI). Signaling + lightweight REST backend + in‑app session management with privacy protections.

</div>

---

## 1. Overview
Inviso is a small, focused example of building an end‑to‑end encrypted (transport level via DTLS/SRTP) peer chat using:

* SwiftUI for UI and state binding
* A WebSocket signaling channel (`SignalingClient`)
* WebRTC DataChannel transport (`PeerConnectionManager`)
* A coordinating state & domain layer (`ChatManager`)
* A thin REST API for creating and accepting “rooms” by short join codes
* Optional ephemeral mode (no local message history retention)
* A privacy overlay that masks UI when the app backgrounds

Messages never transit the REST API after the P2P connection is established; only signaling metadata (SDP + ICE) flows through the WebSocket server. TURN/STUN servers assist NAT traversal.

## 2. Core Features
* Join‑code based session creation + acceptance workflow (pending → accepted → closed)
* WebRTC DataChannel (ordered, reliable) for text messages
* **Ephemeral device IDs per session** (no persistent device tracking)
* **Automatic server purge** when sessions are deleted
* Biometric authentication (Face ID / Touch ID) + passphrase protection
* Automatic ICE gathering + TURN fallback
* Heartbeat & reconnection strategy for signaling
* Session persistence in `UserDefaults` (frontend only; no message storage server‑side)
* Privacy overlay to hide content when app resigns active
* Graceful leave + reconnection suppression to avoid thrash
* Session name synchronization across UI components
* Lightweight modular code (single responsibility objects)

## 3. High‑Level Architecture
```
SwiftUI Views (ChatView, SessionsView, etc.)
	 │
	 ▼  (Published properties / Combine)
 ChatManager  <——>  SignalingClient (WebSocket)  <——>  Signaling Server
	 │                         │
	 │                         └─ JSON messages: connected, join_room, offer/answer, ice_candidate ...
	 ▼
 PeerConnectionManager (WebRTC PeerConnection + DataChannel)
	 │
	 └─ Direct P2P DataChannel (encrypted, DTLS/SRTP stack handled by WebRTC)
```

### Key Components
| Component | Responsibility |
|-----------|----------------|
| `ChatManager` | Orchestrates session lifecycle, REST calls, signaling messages, P2P state, UI‑facing published state. |
| `SignalingClient` | Manages WebSocket connection, heartbeat ping, reconnect logic, JSON encode/decode. |
| `PeerConnectionManager` | Creates & manages `RTCPeerConnection` and `RTCDataChannel`, offers/answers, ICE candidates. |
| `DeviceIDManager` | Manages ephemeral device IDs per session, handles server purge requests on deletion. |
| `AppSecurityManager` | Observes app lifecycle and toggles privacy overlay. |
| `AuthenticationSettingsStore` | Manages biometric and passphrase authentication settings. |
| `PassphraseManager` | Secure passphrase storage and validation using Keychain. |
| SwiftUI Views | Render real‑time state and dispatch user intents (create session, send message, leave room). |

## 4. Session & Connection Lifecycle
1. User creates a session → `ChatSession(status: .pending)` stored locally and POST `/api/rooms` with join code + expiry.
2. Remote peer enters the join code → backend pairs clients → returns `roomid` to second peer; first peer polls (`checkPendingOnServer`) until accepted.
3. When both sides have the `roomId`, the UI triggers `joinRoom(roomId:)` → signaling server orchestrates who is initiator.
4. Initiator creates `RTCPeerConnection` + DataChannel → creates SDP offer → sent over WebSocket.
5. Responder sets remote offer, creates answer → answer sent back.
6. ICE candidates exchanged until connectivity established (STUN/TURN).
7. `PeerConnectionManager` reports connection via `pcmIceStateChanged(connected: true)` → UI shows green status; messages flow P2P.
8. Leave: user taps Leave → `ChatManager.leave(userInitiated:)` closes P2P first, sends `leave_room`, clears room state; if no ack, a timed soft reconnect of signaling occurs.

### State Transitions (simplified)
```
disconnected → (connect) → connecting → (WS 'connected') → connected
connected + no room → (join_room) → room_joined → room_ready → WebRTC negotiation → P2P connected
P2P connected → (leave / peer_left) → no room (messages kept unless ephemeral)
```

## 5. Data Flow (Message Path)
Send:
`ChatView` → `ChatManager.sendMessage()` → `PeerConnectionManager.send()` → WebRTC DataChannel → Remote peer delegate → `ChatManager.pcmDidReceiveMessage` on other device.

Receive:
Remote DataChannel → `PeerConnectionManager` delegate → `ChatManager` appends `ChatMessage` (Published) → SwiftUI auto‑renders.

No message content traverses the signaling server after P2P establishment (only initial negotiation metadata does).

## 6. Reliability & Reconnection Strategies
| Concern | Strategy |
|---------|----------|
| WebSocket liveness | Heartbeat ping every 25s + 10s timeout → triggers `failAndReconnect()` |
| Accidental leave thrash | One‑shot `suppressReconnectOnce` prevents immediate auto reconnect after user leave |
| ICE candidate ordering | Candidates buffered until remote description set (`pending` array) |
| Race on leaving room | P2P closed before signaling leave to avoid renegotiation events mid‑teardown |
| Session polling | `pollPendingAndValidateRooms()` validates pending acceptance + still‑existing rooms |

## 7. Security & Privacy Notes
| Area | Current Approach | Notes |
|------|------------------|-------|
| Transport | WebRTC DTLS + TURN relays | Dynamic TURN creds recommended for production |
| Message storage | In‑memory only (optionally ephemeral) | No message history stored server-side |
| Background privacy | Fullscreen black overlay (`PrivacyOverlayView`) | Biometric re-unlock available via settings |
| Device identity | **Ephemeral IDs per session** | Each session gets unique UUID, cannot be correlated |
| Server cleanup | Automatic purge on deletion | Ephemeral IDs purged from server when sessions deleted |
| Authentication | Optional biometric + passphrase | Face ID / Touch ID + custom passphrase support |
| Error handling | Console prints with `[Component]` tags | Structured logging for debugging |

### Ephemeral Identity System
**Privacy-First Design:** No persistent device ID is stored or transmitted. Each chat session generates a unique ephemeral ID that:
- Cannot be linked back to the device
- Is automatically purged from the server when the session is deleted
- Is cleared during "Erase All Data" operation
- Enables complete session unlinkability

**Server Purge API:** When ephemeral IDs are deleted locally, they are automatically purged from the backend via batch API (`POST /api/user/purge` with `{"deviceIds": [...]}`).

**Session Name Sync:** When you rename a session, the name is synchronized to the ephemeral ID record, ensuring Settings → Privacy → Session Identities always shows current names.

TURN credentials in the source are for development/testing only—rotate and secure in production.

## 8. Persistence Model
Only `ChatSession` array is serialized to `UserDefaults` (`chat.sessions.v1`). Messages are intentionally transient. Ephemeral mode (`isEphemeral`) clears messages upon join, ensuring zero local history.

## 9. Folder Structure (Excerpt)
```
Inviso/
  ChatManager.swift          # Orchestration & state
  Models/ChatModels.swift    # Connection + session models
  Signaling/SignalingClient.swift
  Networking/PeerConnectionManager.swift
  Security/                  # Privacy overlay & lifecycle security
  Services/
    Authentication/          # Biometric + passphrase auth
    Storage/                 # DeviceIDManager, AppDataReset
  Views/                     # SwiftUI interface (ChatView, SessionsView, etc.)
    Settings/                # Settings UI including EphemeralIDsView
  Utilities/                 # Helpers & security notifications
```

## 10. Build & Run
Prerequisites: Xcode 15+, iOS 15+ target.

1. Open `Inviso.xcodeproj` (or the workspace if integrating into a larger app).
2. Ensure Swift Package dependency resolves (`WebRTC` via SPM). If needed: File > Packages > Resolve Package Versions.
3. Run on a physical device or two Simulators (TURN usage may require real networking for NAT scenarios).
4. Create a session on Device A → share the 6‑digit code → accept on Device B → wait for P2P indicator (green dot).

### Swift Package Integration (Library Use)
Add this repo as a remote Swift Package and depend on target `Inviso`. Instantiate `ChatManager()` and inject into your SwiftUI environment.

## 11. Configuration
Edit inside `ChatManager`:
```swift
// Now dynamically configured via ServerConfig.shared.host
// Example: let signaling = SignalingClient(serverURL: "wss://\(ServerConfig.shared.host)")
//          let apiBase = URL(string: "http://\(ServerConfig.shared.host)")!
```
Change ICE servers in `PeerConnectionManager.createPeerConnection`.

Environment‑driven config can be introduced by wrapping these in a struct injected at init.

## 12. Extensibility Ideas
* Multi‑party rooms (SFU / Mesh) – adapt signaling semantics.
* File or image transfer (DataChannel chunking + metadata messages).
* Application‑level E2E encryption (Olm/DoubleRatchet libs) over DataChannel payload.
* Push notifications for pending session acceptance (APNs + backend trigger).
* Analytics & telemetry (with privacy controls and user consent).
* Offline queue (buffer sends until P2P established).
* Theming + accessibility improvements (Dynamic Type, VoiceOver labels for system messages).
* On‑device LLM assistant (iOS 26+) — local inference chat tab (prototype added).
* Message expiration timer beyond 24h default.
* Export/import session configuration (without message history).

## 13. Troubleshooting
| Symptom | Possible Cause | Action |
|---------|----------------|-------|
| Stuck on “Waiting for P2P…” | ICE blocked / TURN unreachable | Verify TURN ports, inspect network logs.
| WebSocket reconnect loop | Server down / heartbeat failing | Check server logs; confirm ping interval alignment.
| Messages not delivered | DataChannel not open | Confirm `isP2PConnected` and renegotiate if needed.
| Session never becomes accepted | Peer didn’t enter code or expired | Poll `checkPendingOnServer` or recreate session.
| Privacy overlay stuck | App lifecycle notification missed | Reproduce; ensure notifications on main thread.

Enable verbose WebRTC logs by configuring `RTCSetMinDebugLogLevel(.verbose)` early (not included by default here).

## 14. Testing Approach (Suggested)
Currently minimal. Recommended next steps:
* Unit test `ChatManager` session persistence & lifecycle edges.
* Mock `SignalingClient` to simulate offer/answer + error conditions.
* UI Tests for Leave confirmation + privacy overlay appearance.

## 15. Roadmap (Proposed)
1. Add structured logging + log viewer.
2. Introduce optional message encryption layer.
3. Support attachments (binary DataChannel frames + MIME labeling).
4. Replace polling with server push for session acceptance.
5. Add automated test suite + CI workflow.
6. Dynamic TURN credentials via ephemeral auth service.

## 16. Contributing
Pull requests welcome. Please:
1. Open an issue describing the change.
2. Keep components small & testable.
3. Avoid introducing 3rd‑party dependencies unless necessary.

## 17. License
Specify your license (e.g., MIT) here. Example:
```
MIT License © 2025 YOUR NAME
```
Replace with actual license text and author details as appropriate.

## 18. Disclaimer
This is a development / demonstration project. Do not ship to production without securing credentials, adding robust error handling, and completing a security review.

---

## 19. Quick Reference (Cheat Sheet)
| Task | Entry Point |
|------|-------------|
| Create session | `ChatManager.createSession` |
| Accept by code | `ChatManager.acceptJoinCode` |
| Join room | `ChatManager.joinRoom` |
| Send message | `ChatManager.sendMessage` |
| Leave room | `ChatManager.leave` |
| Rename session | `ChatManager.renameSession` |
| Delete session | `ChatManager.removeSession` |
| P2P event | `PeerConnectionManagerDelegate` methods |
| Ephemeral ID management | `DeviceIDManager.shared` |
| Server purge | `DeviceIDManager.purgeFromServer` |
| Authentication settings | `AuthenticationSettingsStore.shared` |
| On‑device LLM chat | `OnDeviceLLMManager` via `LLMView` |

---

### On‑Device LLM (Preview)
An experimental tab (`LLM`) showcases a local assistant UI. Implementation notes:

* Manager: `OnDeviceLLMManager` (observable) reuses existing `ChatMessage` model.
* Availability: Gated by `#available(iOS 26, *)` – gracefully degrades with a system message if unsupported.
* Current Logic: Placeholder echo response with artificial delay; wired for future streaming token integration once full FoundationModels API surface is finalized.
* UI: Minimal scrollable transcript + input bar; shows a progress indicator while generating.
* Next Steps: Replace placeholder with real model session initialization, add configurable system prompt, add stop button, implement per‑message streaming updates.

Safety: No external network calls are performed for LLM replies; placeholder text is generated locally.

---

For questions or clarifications, open an issue or extend this README with additional diagrams.
