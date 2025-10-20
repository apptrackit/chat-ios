//
//  ChatManager.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/12/25.
//

import Foundation
import SwiftUI
import WebRTC
import Combine
import CryptoKit
import UIKit
import UserNotifications

@MainActor
class ChatManager: NSObject, ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var messages: [ChatMessage] = []
    @Published var roomId: String = ""
    @Published var isP2PConnected: Bool = false
    @Published var connectionPath: ConnectionPath = .unknown
    @Published var isEphemeral: Bool = false // Manual Room mode: don't keep history
    @Published var remotePeerPresent: Bool = false // Tracks whether the remote peer is currently in the room (P2P established at least once and not yet left)
    @Published var isOnline: Bool = false // True only while signaling WebSocket is connected
    // Sessions (frontend)
    @Published var sessions: [ChatSession] = []
    @Published var activeSessionId: UUID?
    
    // Push notification navigation trigger
    @Published var shouldNavigateToChat: Bool = false
    @Published var shouldNavigateToSessions: Bool = false
    
    // Encryption (E2EE)
    @Published var isEncryptionReady: Bool = false // True when key exchange completes and encryption is active
    @Published var keyExchangeInProgress: Bool = false // True during key negotiation

    // Message retention policy (per session)
    @Published var currentRetentionPolicy: MessageRetentionPolicy = .noStorage
    @Published var peerRetentionPolicy: MessageRetentionPolicy? = nil // Peer's policy (nil if not synced yet)
    
    // Message storage
    private let messageStorage = MessageStorage.shared
    private var expirationCleanupTimer: Timer?

    // Components (dynamic server config)
    private var signaling: SignalingClient
    private var apiBase: URL { URL(string: "https://\(ServerConfig.shared.host)")! }
    private let pcm = PeerConnectionManager()
    private let apiClient = APIClient()
    
    // Encryption components
    private var keyExchangeHandler: KeyExchangeHandler?
    private let messageEncryptor = MessageEncryptor()
    private let encryptionKeychain = EncryptionKeychain()
    // Track encryption state per session (roomId -> EncryptionState)
    private var encryptionStates: [String: EncryptionState] = [:]
    // Store session ID (UUID) for current room for Keychain operations
    private var currentSessionKeyId: UUID?
    // Queue for received key_exchange messages before our keypair is ready
    private var pendingPeerPublicKey: (publicKey: String, sessionId: String)?

    // State
    private var clientId: String?
    private var isAwaitingLeaveAck = false
    private var pendingJoinRoomId: String?
    private var suppressReconnectOnce = false
    private var hadP2POnce = false
    // Deep link join waiting confirmation
    @Published var pendingDeepLinkCode: String? = nil
    // ChatView lifecycle tracking to defer P2P connection
    private(set) var isChatViewActive = false
    private var pendingRoomReadyIsInitiator: Bool?
    
    // Server-assigned WebRTC initiator role (first user to join = initiator)
    private var serverAssignedIsInitiator: Bool? = nil
    
    // Track disconnection state for automatic rejoin
    private var wasInRoomBeforeDisconnect: String? = nil
    private var appLifecycleCancellables = Set<AnyCancellable>()

    override init() {
    self.signaling = SignalingClient(serverURL: "wss://\(ServerConfig.shared.host)")
    super.init()
    signaling.delegate = self
        pcm.delegate = self
        loadSessions()
        setupKeyExchangeObservers()
        setupAppLifecycleObservers()
        setupPushNotificationObservers()
        setupRetentionCleanupTimer()
        
        // Sync pending notifications from Notification Service Extension
        syncPendingNotifications()
        
        // Clean up old notifications on init
        clearOldNotifications()
        
        // Clear notification center (cards) but keep badge
        clearNotificationCenter()
    }

    deinit {
        // Note: disconnect/close are @MainActor isolated but deinit is nonisolated.
        // This is acceptable for cleanup as the object is being destroyed.
        // The methods will be called synchronously on deallocation.
    }

    // Public API
    func connect() { signaling.connect() }

    func disconnect() {
        signaling.disconnect()
        pcm.close()
        messages.removeAll()
        roomId = ""
        isP2PConnected = false
    remotePeerPresent = false
        connectionStatus = .disconnected
        clientId = nil
        pendingJoinRoomId = nil
        isAwaitingLeaveAck = false
        isChatViewActive = false
        pendingRoomReadyIsInitiator = nil
        serverAssignedIsInitiator = nil
        pendingPeerPublicKey = nil
        
        // Clear encryption state
        cleanupEncryption()
    }

    // Change server host at runtime. Disconnects current signaling and rebuilds client.
    func changeServerHost(to newHostRaw: String) {
        let oldHost = ServerConfig.shared.host
        ServerConfig.shared.updateHost(newHostRaw)
        guard ServerConfig.shared.host != oldHost else { return }
        // Fully disconnect current signaling + P2P
        signaling.disconnect()
        pcm.close()
        isP2PConnected = false
        remotePeerPresent = false
        connectionStatus = .disconnected
        clientId = nil
        // Recreate signaling client with new host
        signaling = SignalingClient(serverURL: "wss://\(ServerConfig.shared.host)")
        signaling.delegate = self
    }

    func joinRoom(roomId: String) {
    if connectionStatus != .connected { return } // Block join attempts while offline/disconnected
    if isEphemeral { messages.removeAll() }
        self.roomId = roomId
        // Note: Don't update activity here - only update when E2EE is established and messages are exchanged
        
        // Load stored messages for this session based on retention policy
        if let sessionId = activeSessionId, currentRetentionPolicy != .noStorage {
            do {
                messages = try messageStorage.loadMessages(for: sessionId)
                print("[ChatManager] 📖 Loaded \(messages.count) stored messages")
            } catch {
                print("[ChatManager] ⚠️ Failed to load messages: \(error)")
            }
        }
        
        // Find the session's ephemeral device ID to send to backend for push notification matching
        let deviceId = sessions.first(where: { $0.roomId == roomId })?.ephemeralDeviceId
        
        if let deviceId = deviceId {
            signaling.send(["type": "join_room", "roomId": roomId, "deviceId": deviceId])
            print("[ChatManager] 🔌 Joining room with deviceId: \(deviceId.prefix(8))...")
        } else {
            signaling.send(["type": "join_room", "roomId": roomId])
            print("[ChatManager] ⚠️ Joining room without deviceId (not found in sessions)")
        }
    }

    func leave(userInitiated: Bool = false) {
        if userInitiated { 
            suppressReconnectOnce = true
            // User explicitly left - clear auto-rejoin state
            wasInRoomBeforeDisconnect = nil
        }
        guard !roomId.isEmpty else { return }
        
        // Save messages before clearing if retention policy is not noStorage
        if let sessionId = activeSessionId, currentRetentionPolicy != .noStorage {
            do {
                try messageStorage.saveMessages(messages, for: sessionId)
                print("[ChatManager] 💾 Saved \(messages.count) messages before leaving")
            } catch {
                print("[ChatManager] ⚠️ Failed to save messages: \(error)")
            }
        }
        
    messages.removeAll()
        // Stop P2P first to avoid any renegotiation or events during leave.
        pcm.close()
        isP2PConnected = false
    remotePeerPresent = false
        hadP2POnce = false
        
        // Clean up encryption for this session
        cleanupEncryption()
        
        // Clear any pending room_ready that wasn't processed
        pendingRoomReadyIsInitiator = nil
        // Send leave to server and clear local room immediately.
        isAwaitingLeaveAck = true
        signaling.send(["type": "leave_room"])        
        let currentRoom = roomId
        roomId = ""
        // Fallback: gently reconnect WS if no ack after a short delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if self.isAwaitingLeaveAck && self.connectionStatus == .connected && currentRoom.isEmpty == false && self.suppressReconnectOnce == false {
                self.signaling.disconnect()
                self.signaling.connect()
            }
            // Reset the one-shot suppress flag after evaluating fallback.
            self.suppressReconnectOnce = false
        }
    }

    func sendMessage(_ text: String) {
        guard isP2PConnected else { return }
        guard isEncryptionReady else {
            print("⚠️ Encryption not ready, cannot send message")
            return
        }
        
        guard var state = encryptionStates[roomId],
              let sessionKeyId = currentSessionKeyId else {
            print("⚠️ No encryption state for current room")
            return
        }
        
        do {
            // LOG: Show plaintext being sent
            print("📤 [E2EE] Sending message: \"\(text)\"")
            
            // Get session key from Keychain
            guard let sessionKeyData = try encryptionKeychain.getKey(for: .sessionKey, sessionId: sessionKeyId),
                  sessionKeyData.count == EncryptionConstants.sessionKeySize else {
                throw EncryptionError.sessionKeyNotFound
            }
            let sessionKey = SymmetricKey(data: sessionKeyData)
            
            // Increment send counter
            let counter = state.sendCounter
            state.sendCounter += 1
            encryptionStates[roomId] = state
            
            // DIAGNOSTIC: Log key being used for encryption
            let keyBytes = sessionKeyData.prefix(8).base64EncodedString()
            print("🔐 [DEBUG] Encrypting with session key: \(keyBytes)..., counter: \(counter)")
            
            // Encrypt the message
            let wireFormat = try messageEncryptor.encrypt(
                text,
                sessionKey: sessionKey,
                counter: counter,
                direction: .send
            )
            
            // Serialize to JSON
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(wireFormat)
            
            // LOG: Show encrypted data
            let encryptedDataHex = jsonData.prefix(64).map { String(format: "%02x", $0) }.joined()
            let encryptedDataBase64 = jsonData.prefix(128).base64EncodedString()
            print("📦 [E2EE] Encrypted data (\(jsonData.count) bytes)")
            print("   Hex (first 64 bytes): \(encryptedDataHex)")
            print("   Base64 (first 128 bytes): \(encryptedDataBase64)")
            
            // Send encrypted binary data over DataChannel
            let ok = pcm.sendData(jsonData)
            if ok {
                // Calculate expiration date based on current retention policy
                let expiresAt = currentRetentionPolicy.expirationDate(from: Date())
                
                messages.append(ChatMessage(text: text, timestamp: Date(), isFromSelf: true, expiresAt: expiresAt))
                // Update activity for active session
                if let sessionId = activeSessionId {
                    updateSessionActivity(sessionId)
                    
                    // Save messages if retention policy is not noStorage
                    if currentRetentionPolicy != .noStorage {
                        do {
                            try messageStorage.saveMessages(messages, for: sessionId)
                        } catch {
                            print("[ChatManager] ⚠️ Failed to save messages: \(error)")
                        }
                    }
                }
            }
        } catch {
            print("❌ Failed to encrypt message: \(error)")
        }
    }
    
    func sendLocation(_ location: LocationData) {
        guard isP2PConnected else { return }
        guard isEncryptionReady else {
            print("⚠️ Encryption not ready, cannot send location")
            return
        }
        
        guard var state = encryptionStates[roomId],
              let sessionKeyId = currentSessionKeyId else {
            print("⚠️ No encryption state for current room")
            return
        }
        
        // Convert location to JSON string
        guard let locationJSON = location.toJSONString() else {
            print("❌ Failed to serialize location data")
            return
        }
        
        do {
            print("📍 [E2EE] Sending location: \(location.latitude), \(location.longitude)")
            
            // Get session key from Keychain
            guard let sessionKeyData = try encryptionKeychain.getKey(for: .sessionKey, sessionId: sessionKeyId),
                  sessionKeyData.count == EncryptionConstants.sessionKeySize else {
                throw EncryptionError.sessionKeyNotFound
            }
            let sessionKey = SymmetricKey(data: sessionKeyData)
            
            // Increment send counter
            let counter = state.sendCounter
            state.sendCounter += 1
            encryptionStates[roomId] = state
            
            // Encrypt the location JSON
            let wireFormat = try messageEncryptor.encrypt(
                locationJSON,
                sessionKey: sessionKey,
                counter: counter,
                direction: .send
            )
            
            // Serialize to JSON
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(wireFormat)
            
            print("📦 [E2EE] Encrypted location data (\(jsonData.count) bytes)")
            
            // Send encrypted binary data over DataChannel
            let ok = pcm.sendData(jsonData)
            if ok {
                // Add location message to local chat
                var msg = ChatMessage(text: "", timestamp: Date(), isFromSelf: true)
                msg.locationData = location
                messages.append(msg)
                
                // Update activity for active session
                if let sessionId = activeSessionId {
                    updateSessionActivity(sessionId)
                }
            }
        } catch {
            print("❌ Failed to encrypt location: \(error)")
        }
    }
    
    func sendVoice(_ voice: VoiceData) {
        guard isP2PConnected else { return }
        guard isEncryptionReady else {
            print("⚠️ Encryption not ready, cannot send voice")
            return
        }
        
        guard var state = encryptionStates[roomId],
              let sessionKeyId = currentSessionKeyId else {
            print("⚠️ No encryption state for current room")
            return
        }
        
        // Convert voice to JSON string
        guard let voiceJSON = voice.toJSONString() else {
            print("❌ Failed to serialize voice data")
            return
        }
        
        do {
            print("🎤 [E2EE] Sending voice message: \(voice.duration)s")
            
            // Get session key from Keychain
            guard let sessionKeyData = try encryptionKeychain.getKey(for: .sessionKey, sessionId: sessionKeyId),
                  sessionKeyData.count == EncryptionConstants.sessionKeySize else {
                throw EncryptionError.sessionKeyNotFound
            }
            let sessionKey = SymmetricKey(data: sessionKeyData)
            
            // Increment send counter
            let counter = state.sendCounter
            state.sendCounter += 1
            encryptionStates[roomId] = state
            
            // Encrypt the voice JSON
            let wireFormat = try messageEncryptor.encrypt(
                voiceJSON,
                sessionKey: sessionKey,
                counter: counter,
                direction: .send
            )
            
            // Serialize to JSON
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(wireFormat)
            
            print("📦 [E2EE] Encrypted voice data (\(jsonData.count) bytes)")
            
            // Send encrypted binary data over DataChannel
            let ok = pcm.sendData(jsonData)
            if ok {
                // Add voice message to local chat
                var msg = ChatMessage(text: "", timestamp: Date(), isFromSelf: true)
                msg.voiceData = voice
                messages.append(msg)
                
                // Update activity for active session
                if let sessionId = activeSessionId {
                    updateSessionActivity(sessionId)
                }
            }
        } catch {
            print("❌ Failed to encrypt voice: \(error)")
        }
    }

    // MARK: - ChatView Lifecycle Management
    /// Called when ChatView appears. If we have a pending room_ready, process it now.
    func chatViewDidAppear() {
        isChatViewActive = true
        if let isInitiator = pendingRoomReadyIsInitiator {
            pendingRoomReadyIsInitiator = nil
            handleRoomReady(isInitiator: isInitiator)
        }
    }

    /// Called when ChatView disappears. Clears the active flag.
    func chatViewDidDisappear() {
        isChatViewActive = false
        // If user left before P2P was established, clear pending room_ready
        // This prevents auto-connecting when they return later
        if pendingRoomReadyIsInitiator != nil && !isP2PConnected {
            pendingRoomReadyIsInitiator = nil
        }
    }

    // MARK: - Full local reset for Settings > Erase All Data
    func eraseLocalState() {
        // Disconnect transports and clear runtime state
        disconnect()
        // Clear sessions and persisted store
        sessions.removeAll()
        activeSessionId = nil
        persistSessions()
        // Clear all ephemeral IDs
        DeviceIDManager.shared.clearAllEphemeralIDs()
        // Clear all stored messages
        messageStorage.eraseAll()
    }

    // MARK: - Deep Link Handling (inviso://join/<code>)
    /// Entry point for handling a custom URL of the form inviso://join/<6-digit-code>
    /// Accepts the code, creates/updates a session, and attempts to join if room resolved.
    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "inviso" else { return }
        // Support both forms:
        // 1) inviso://join/123456  -> host = "join", path = "/123456"
        // 2) inviso://join/123456 (previous parser expected path components ["join","123456"] if constructed differently)
        // First: host style (most common when user scans QR with iOS Camera)
        if let host = url.host?.lowercased(), host == "join" {
            let codeCandidate = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !codeCandidate.isEmpty { queueDeepLinkCode(codeCandidate); return }
        }
        // Fallback: path starts with join
        let trimmedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = trimmedPath.split(separator: "/")
        if parts.count == 2, parts[0].lowercased() == "join" {
            queueDeepLinkCode(String(parts[1]))
        }
    }

    private func queueDeepLinkCode(_ code: String) {
        guard code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else { return }
        pendingDeepLinkCode = code
    }

    private func handleJoinCodeFromDeepLink(code: String) {
        // Validate 6-digit pattern
        guard code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else { return }
        // If already have an accepted or pending session with this code, select it
        if let existing = sessions.first(where: { $0.code == code && $0.status != .closed && $0.status != .expired }) {
            activeSessionId = existing.id
            // DON'T auto-join WebSocket - user must explicitly open ChatView
            // if let rid = existing.roomId { joinRoom(roomId: rid) }
            return
        }
        // Otherwise attempt accept flow
        Task { [weak self] in
            guard let self = self else { return }
            if let result = await self.acceptJoinCode(code) {
                let session = self.addAcceptedSession(name: nil, code: code, roomId: result.roomId, ephemeralId: result.ephemeralId, isCreatedByMe: false)
                // DON'T auto-join WebSocket room yet - wait until user opens ChatView
                // self.joinRoom(roomId: result.roomId)
                self.activeSessionId = session.id
                // Register ephemeral ID
                DeviceIDManager.shared.registerEphemeralID(result.ephemeralId, sessionName: nil, code: code)
            } else {
                // Create a pending session placeholder so UI can show waiting state
                let pending = ChatSession(name: nil, code: code, createdAt: Date(), expiresAt: Date().addingTimeInterval(5*60), status: .pending, isCreatedByMe: false)
                self.sessions.insert(pending, at: 0)
                self.activeSessionId = pending.id
                self.persistSessions()
            }
            self.pendingDeepLinkCode = nil
        }
    }

    // Called by UI after user confirms deep link join
    func confirmPendingDeepLinkJoin() {
        guard let code = pendingDeepLinkCode else { return }
    guard connectionStatus == .connected else { return }
        handleJoinCodeFromDeepLink(code: code)
    }
    
    // Called by UI for deep link join with naming step
    func confirmPendingDeepLinkJoinWithNaming(code: String) async -> Bool {
        guard connectionStatus == .connected else { return false }
        
        // Validate 6-digit pattern
        guard code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else { return false }
        
        // If already have an accepted or pending session with this code, select it
        if let existing = sessions.first(where: { $0.code == code && $0.status != .closed && $0.status != .expired }) {
            activeSessionId = existing.id
            // DON'T auto-join WebSocket - user must explicitly open ChatView
            // if let rid = existing.roomId { joinRoom(roomId: rid) }
            return true
        }
        
        // Otherwise attempt accept flow
        if let result = await acceptJoinCode(code) {
            let session = addAcceptedSession(name: nil, code: code, roomId: result.roomId, ephemeralId: result.ephemeralId, isCreatedByMe: false)
            // DON'T auto-join WebSocket room yet - wait until user opens ChatView
            // joinRoom(roomId: result.roomId)
            activeSessionId = session.id
            // Register ephemeral ID
            DeviceIDManager.shared.registerEphemeralID(result.ephemeralId, sessionName: nil, code: code)
            return true
        } else {
            // Create a pending session placeholder so UI can show waiting state
            let pending = ChatSession(name: nil, code: code, createdAt: Date(), expiresAt: Date().addingTimeInterval(5*60), status: .pending, isCreatedByMe: false)
            sessions.insert(pending, at: 0)
            activeSessionId = pending.id
            persistSessions()
            return false
        }
    }

    func cancelPendingDeepLinkJoin() { pendingDeepLinkCode = nil }

    // MARK: - Sessions (frontend only)
    func createSession(name: String?, minutes: Int, code: String) -> ChatSession {
        // Prevent creation while offline: simply return a placeholder that won't be persisted/used.
        guard connectionStatus == .connected else {
            // Could surface a UI error; here we no-op and return a transient object
            return ChatSession(name: name, code: code, createdAt: Date(), expiresAt: nil, status: .pending, isCreatedByMe: true)
        }
        let expires: Date? = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes) * 60.0) : nil
        let session = ChatSession(name: name, code: code, createdAt: Date(), expiresAt: expires, status: .pending, isCreatedByMe: true)
        sessions.insert(session, at: 0)
        activeSessionId = session.id
        // Register ephemeral ID
        DeviceIDManager.shared.registerEphemeralID(session.ephemeralDeviceId, sessionName: name, code: code)
        persistSessions()
        Task { await createPendingOnServer(session: session, originalMinutes: minutes) }
        return session
    }

    func markActiveSessionAccepted() {
        guard let id = activeSessionId, let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        if sessions[idx].status != .accepted {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                sessions[idx].status = .accepted
            }
            // Set first connected timestamp if not already set
            if sessions[idx].firstConnectedAt == nil {
                sessions[idx].firstConnectedAt = Date()
            }
            persistSessions()
        }
    }

    func closeActiveSession() {
        guard let id = activeSessionId, let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            sessions[idx].status = .closed
        }
        // Set closed timestamp
        if sessions[idx].closedAt == nil {
            sessions[idx].closedAt = Date()
        }
        activeSessionId = nil
    // If room exists, call backend delete
    if let rid = sessions[idx].roomId { Task { await deleteRoomOnServer(roomId: rid) } }
    persistSessions()
    }

    func selectSession(_ session: ChatSession) {
        activeSessionId = session.id
    }

    /// Updates lastActivityDate for a session and moves it to top of list
    func updateSessionActivity(_ sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].lastActivityDate = Date()
        // Move to top of list by removing and reinserting
        let session = sessions.remove(at: idx)
        sessions.insert(session, at: 0)
        persistSessions()
    }

    func renameSession(_ session: ChatSession, newName: String?) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx].name = newName
        persistSessions()
        // Also update the ephemeral ID record with the new name
        DeviceIDManager.shared.updateSessionName(ephemeralId: session.ephemeralDeviceId, newName: newName)
    }

    func removeSession(_ session: ChatSession) {
        if let rid = session.roomId { Task { await deleteRoomOnServer(roomId: rid) } }
        // Purge ephemeral ID from server, then remove locally
        Task {
            await DeviceIDManager.purgeFromServer(ephemeralId: session.ephemeralDeviceId)
            await MainActor.run {
                DeviceIDManager.shared.removeEphemeralID(session.ephemeralDeviceId)
            }
        }
        sessions.removeAll { $0.id == session.id }
        if activeSessionId == session.id { activeSessionId = nil }
        persistSessions()
    }
    
    /// Pin a session - adds it to pinned section with newest pinnedOrder
    func pinSession(_ session: ChatSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        guard !sessions[idx].isPinned else { return } // Already pinned
        
        // Get the highest pinnedOrder and add 1 (new pins go to bottom of pinned list)
        let maxOrder = sessions.compactMap { $0.pinnedOrder }.max() ?? -1
        sessions[idx].isPinned = true
        sessions[idx].pinnedOrder = maxOrder + 1
        persistSessions()
    }
    
    /// Unpin a session - removes from pinned section and reorders remaining pinned items
    func unpinSession(_ session: ChatSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        guard sessions[idx].isPinned else { return } // Not pinned
        
        let removedOrder = sessions[idx].pinnedOrder
        sessions[idx].isPinned = false
        sessions[idx].pinnedOrder = nil
        
        // Reorder remaining pinned items to fill the gap
        if let removed = removedOrder {
            for i in sessions.indices {
                if sessions[i].isPinned, let order = sessions[i].pinnedOrder, order > removed {
                    sessions[i].pinnedOrder = order - 1
                }
            }
        }
        persistSessions()
    }
    
    /// Reorder pinned sessions by moving a session from one position to another
    func movePinnedSession(from source: IndexSet, to destination: Int, in pinnedSessions: [ChatSession]) {
        guard !source.isEmpty else { return }
        
        // Create mutable copy of pinned sessions
        var reordered = pinnedSessions
        reordered.move(fromOffsets: source, toOffset: destination)
        
        // Update pinnedOrder for all pinned sessions based on new order
        for (newOrder, session) in reordered.enumerated() {
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[idx].pinnedOrder = newOrder
            }
        }
        persistSessions()
    }
    
    // MARK: - Notification Management
    
    /// Sync pending notifications from Notification Service Extension
    /// This ensures notifications are tracked even when app wasn't open
    func syncPendingNotifications() {
        let appGroupId = "group.com.31b4.inviso"
        let pendingNotificationsKey = "pending_notifications"
        
        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            print("[ChatManager] ❌ Failed to access App Group UserDefaults")
            return
        }
        
        // Load pending notifications
        guard let pendingNotifications = sharedDefaults.array(forKey: pendingNotificationsKey) as? [[String: Any]],
              !pendingNotifications.isEmpty else {
            print("[ChatManager] ℹ️ No pending notifications to sync")
            return
        }
        
        print("[ChatManager] 📥 Syncing \(pendingNotifications.count) pending notifications...")
        
        var syncedCount = 0
        
        for notificationDict in pendingNotifications {
            guard let roomId = notificationDict["roomId"] as? String,
                  let timestamp = notificationDict["receivedAt"] as? TimeInterval else {
                continue
            }
            
            let receivedAt = Date(timeIntervalSince1970: timestamp)
            
            // Find the session for this roomId
            guard let sessionIndex = sessions.firstIndex(where: { $0.roomId == roomId }) else {
                print("[ChatManager] ⚠️ No session found for roomId: \(roomId.prefix(8))")
                continue
            }
            
            // Check if we already have this notification (avoid duplicates)
            let alreadyExists = sessions[sessionIndex].notifications.contains { notification in
                abs(notification.receivedAt.timeIntervalSince(receivedAt)) < 5 // Within 5 seconds
            }
            
            if !alreadyExists {
                let notification = SessionNotification(receivedAt: receivedAt)
                sessions[sessionIndex].notifications.append(notification)
                syncedCount += 1
                print("[ChatManager] ✅ Synced notification for: \(sessions[sessionIndex].displayName)")
            }
        }
        
        if syncedCount > 0 {
            persistSessions()
            print("[ChatManager] 📥 Synced \(syncedCount) new notifications")
        }
        
        // Clear pending notifications from App Group storage
        sharedDefaults.removeObject(forKey: pendingNotificationsKey)
        sharedDefaults.synchronize()
        print("[ChatManager] 🗑️ Cleared pending notifications from App Group")
    }
    
    /// Clear iOS notification center cards only (does not affect badge count)
    func clearNotificationCenter() {
        // Remove all delivered notifications from notification center
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        print("[ChatManager] � Cleared notification center cards (badge unchanged)")
    }
    
    /// Reset server-side badge counts when app opens
    private func resetServerBadgeCounts() async {
        // Use ephemeral device ID from any active session
        // Server will reset badges for all rooms associated with this device
        guard let deviceId = sessions.first?.ephemeralDeviceId else {
            print("[ChatManager] ⚠️ No active sessions to reset badges for")
            return
        }
        
        await apiClient.resetBadgeCount(deviceId: deviceId)
    }
    
    /// Sync server-side badge to match local unread count
    private func syncServerBadgeCount() async {
        guard let session = sessions.first, let _ = session.roomId else {
            print("[ChatManager] ⚠️ No active session to sync badge for")
            return
        }
        
        // Calculate total unread count
        let totalUnread = sessions.reduce(0) { $0 + $1.unreadNotificationCount }
        
        // For now, we reset server badges when local count is 0
        // This prevents accumulation issues
        if totalUnread == 0 {
            await apiClient.resetBadgeCount(deviceId: session.ephemeralDeviceId)
            print("[ChatManager] 🔄 Reset server badge (local unread: 0)")
        } else {
            print("[ChatManager] 🔄 Server badge will continue from current (local unread: \(totalUnread))")
        }
    }
    
    /// Reset server-side badge for a specific room
    private func resetServerBadgeForRoom(roomId: String, deviceId: String) async {
        // Call API to reset badge for specific room
        // Note: Current API resets all badges, but we can add a room-specific endpoint later
        // For now, we just update local state and the next notification will sync properly
        print("[ChatManager] 🔄 Would reset server badge for room: \(roomId.prefix(8))")
    }
    
    /// Mark all notifications for a session as viewed
    func markSessionNotificationsAsViewed(sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        
        let now = Date()
        var hasChanges = false
        
        for i in sessions[idx].notifications.indices {
            if sessions[idx].notifications[i].viewedAt == nil {
                sessions[idx].notifications[i].viewedAt = now
                hasChanges = true
            }
        }
        
        if hasChanges {
            print("[ChatManager] 📖 Marked \(sessions[idx].notifications.count) notifications as viewed for session: \(sessions[idx].displayName)")
            persistSessions()
            updateBadgeCount()
        }
    }
    
    /// Clear old notifications (older than 7 days)
    func clearOldNotifications() {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        var hasChanges = false
        
        for i in sessions.indices {
            let originalCount = sessions[i].notifications.count
            sessions[i].notifications.removeAll { $0.receivedAt < sevenDaysAgo }
            if sessions[i].notifications.count != originalCount {
                hasChanges = true
            }
        }
        
        if hasChanges {
            print("[ChatManager] 🗑️ Cleared old notifications (older than 7 days)")
            persistSessions()
            // No need to update badge - it's cleared when app opens
        }
    }
    
    /// Update iOS badge count based on unread notifications
    /// Update iOS badge count to match total unread notifications
    /// Also saves current badge to App Group so Notification Service Extension can continue from there
    /// NOTE: This is only used internally - badge is cleared when app opens
    private func updateBadgeCount() {
        let totalUnread = sessions.reduce(0) { $0 + $1.unreadNotificationCount }
        
        // Save current badge count to App Group for Notification Service Extension
        let appGroupId = "group.com.31b4.inviso"
        let currentBadgeKey = "current_badge_count"
        if let sharedDefaults = UserDefaults(suiteName: appGroupId) {
            sharedDefaults.set(totalUnread, forKey: currentBadgeKey)
            sharedDefaults.synchronize()
            print("[ChatManager] 💾 Saved badge count to App Group: \(totalUnread)")
        }
        
        Task {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(totalUnread)
                print("[ChatManager] 🔴 Updated badge count to: \(totalUnread)")
            } catch {
                print("[ChatManager] ❌ Failed to update badge count: \(error)")
            }
        }
    }
    
    /// Clear all notifications for a specific session
    func clearSessionNotifications(sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        
        if !sessions[idx].notifications.isEmpty {
            sessions[idx].notifications.removeAll()
            print("[ChatManager] 🗑️ Cleared all notifications for session: \(sessions[idx].displayName)")
            persistSessions()
            updateBadgeCount()
        }
    }

    /// Create and persist an accepted session (used for client2 joining by code, or when we already have roomId)
    @discardableResult
    func addAcceptedSession(name: String?, code: String, roomId: String, ephemeralId: String, isCreatedByMe: Bool) -> ChatSession {
        let s = ChatSession(name: name, code: code, roomId: roomId, createdAt: Date(), expiresAt: nil, status: .accepted, isCreatedByMe: isCreatedByMe, ephemeralDeviceId: ephemeralId)
        sessions.insert(s, at: 0)
        activeSessionId = s.id
        persistSessions()
        return s
    }
    
    // MARK: - Active Session Helpers
    
    /// Get the currently active session
    var activeSession: ChatSession? {
        guard let id = activeSessionId else { return nil }
        return sessions.first(where: { $0.id == id })
    }
    
    /// Get the display name for the active session
    var activeSessionDisplayName: String {
        activeSession?.displayName ?? "Chat"
    }

    // MARK: - Backend REST integration
    private func createPendingOnServer(session: ChatSession, originalMinutes: Int) async {
        let joinid = session.code
        // Use original minutes value directly (more accurate than recalculating)
        let expiresInSeconds = originalMinutes * 60
        let client1 = session.ephemeralDeviceId // Use ephemeral ID for privacy
        
        // Get device token for push notifications
        let deviceToken = PushNotificationManager.shared.getDeviceToken()
        
        // Debug logging
        if let token = deviceToken {
            print("[ChatManager] 📤 Creating room with device token: \(token.prefix(16))...")
        } else {
            print("[ChatManager] ⚠️ Creating room WITHOUT device token - push notifications will not work!")
        }
        
        do {
            // Use APIClient instead of direct URLSession for better token handling
            try await apiClient.createRoom(
                joinCode: joinid,
                expiresInSeconds: expiresInSeconds,
                clientID: client1,
                deviceToken: deviceToken
            )
            
            if deviceToken != nil {
                print("[ChatManager] ✅ Room created with push notification support")
            }
        } catch {
            print("[ChatManager] ❌ createPending error: \(error)")
        }
    }

    func acceptJoinCode(_ code: String) async -> (roomId: String, ephemeralId: String)? {
        let client2 = UUID().uuidString // Generate new ephemeral ID for this session
        
        // Get device token for push notifications
        let deviceToken = PushNotificationManager.shared.getDeviceToken()
        
        // Debug logging
        if let token = deviceToken {
            print("[ChatManager] 📤 Accepting room with device token: \(token.prefix(16))...")
        } else {
            print("[ChatManager] ⚠️ Accepting room WITHOUT device token - push notifications will not work!")
        }
        
        // Use APIClient for better token handling
        if let roomId = await apiClient.acceptJoinCode(code, clientID: client2, deviceToken: deviceToken) {
            if deviceToken != nil {
                print("[ChatManager] ✅ Room accepted with push notification support")
            }
            return (roomId, client2)
        }
        
        return nil
    }

    enum PendingCheckResult {
        case accepted(roomId: String)
        case stillPending
        case expired
        case error
    }

    func checkPendingOnServer(session: ChatSession) async -> PendingCheckResult {
        let client1 = session.ephemeralDeviceId
        var req = URLRequest(url: apiBase.appendingPathComponent("/api/rooms/check"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["joinid": session.code, "client1": client1])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .error }
            if http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rid = json["roomid"] as? String {
                    return .accepted(roomId: rid)
                }
                return .error
            }
            if http.statusCode == 204 { return .stillPending }
            if http.statusCode == 404 { return .expired }
        } catch { print("checkPending error: \(error)") }
        return .error
    }

    func getRoom(roomId: String) async -> (client1: String, client2: String)? {
        guard var comps = URLComponents(url: apiBase.appendingPathComponent("/api/rooms"), resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [URLQueryItem(name: "roomid", value: roomId)]
        guard let url = comps.url else { return nil }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let c1 = json["client1"] as? String, let c2 = json["client2"] as? String { return (c1, c2) }
        } catch { print("getRoom error: \(error)") }
        return nil
    }

    func deleteRoomOnServer(roomId: String) async {
        var req = URLRequest(url: apiBase.appendingPathComponent("/api/rooms"))
        req.httpMethod = "DELETE"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["roomid": roomId])
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Polling and housekeeping
    func pollPendingAndValidateRooms() {
        // If we're not online, skip polling to avoid falsely closing rooms due to transient offline/unreachable state.
        guard connectionStatus == .connected else { return }
        Task {
            // 1) For each pending session, check acceptance
            for i in sessions.indices {
                let s = sessions[i]
                if s.status == .pending {
                    let result = await checkPendingOnServer(session: s)
                    switch result {
                    case .accepted(let roomId):
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                            sessions[i].status = .accepted
                        }
                        sessions[i].roomId = roomId
                        // Set first connected timestamp if not already set
                        if sessions[i].firstConnectedAt == nil {
                            sessions[i].firstConnectedAt = Date()
                        }
                        persistSessions()
                    case .expired:
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                            sessions[i].status = .expired
                        }
                        persistSessions()
                    case .stillPending, .error:
                        break // Keep current state
                    }
                }
            }
            // 2) For accepted sessions with roomId, verify room still exists
            for i in sessions.indices {
                let s = sessions[i]
                if s.status == .accepted, let rid = s.roomId {
                    switch await getRoomStatus(rid) {
                    case .exists:
                        break // all good
                    case .notFound:
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                            sessions[i].status = .closed
                        }
                        sessions[i].roomId = nil
                        // Set closed timestamp if not already set
                        if sessions[i].closedAt == nil {
                            sessions[i].closedAt = Date()
                        }
                        persistSessions()
                    case .unreachable:
                        // Do nothing; keep current state. We'll re-validate when back online.
                        break
                    }
                }
            }
            // 3) Prune ephemeral IDs for closed/removed sessions
            let activeEphemeralIDs = Set(sessions.filter { $0.status != .closed && $0.status != .expired }.map { $0.ephemeralDeviceId })
            DeviceIDManager.shared.pruneEphemeralIDs(activeSessionIDs: activeEphemeralIDs)
        }
    }

    // MARK: - Persistence
    private let storeKey = "chat.sessions.v1"
    private let appGroupId = "group.com.31b4.inviso"
    
    /// Access shared UserDefaults for App Group (used by Notification Service Extension)
    private var sharedDefaults: UserDefaults? {
        return UserDefaults(suiteName: appGroupId)
    }
    
    private func persistSessions() {
        do {
            let data = try JSONEncoder().encode(sessions)
            // Save to both standard UserDefaults (for backward compatibility) and App Group
            UserDefaults.standard.set(data, forKey: storeKey)
            // Save to App Group so Notification Service Extension can access it
            sharedDefaults?.set(data, forKey: storeKey)
        } catch {
            print("persistSessions error: \(error)")
        }
    }
    
    private func loadSessions() {
        // Try loading from App Group first (shared), fall back to standard UserDefaults
        let data = sharedDefaults?.data(forKey: storeKey) ?? UserDefaults.standard.data(forKey: storeKey)
        if let data = data, let arr = try? JSONDecoder().decode([ChatSession].self, from: data) {
            self.sessions = arr
        }
    }

    // MARK: - P2P Connection Handling
    /// Establishes the WebRTC peer connection when room is ready
    private func handleRoomReady(isInitiator: Bool) {
        // Start key exchange BEFORE establishing P2P connection
        startKeyExchange(isInitiator: isInitiator)
        // P2P connection will be created after key exchange completes
    }
    
    // MARK: - Encryption (E2EE Key Exchange & Message Encryption)
    
    private func setupKeyExchangeObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyExchangeReceived(_:)),
            name: .keyExchangeReceived,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyExchangeCompleteReceived(_:)),
            name: .keyExchangeCompleteReceived,
            object: nil
        )
    }
    
    private func setupAppLifecycleObservers() {
        // Observe when app becomes active (returns from background)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAppBecameActive()
                }
            }
            .store(in: &appLifecycleCancellables)
        
        // Observe when app enters foreground
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAppWillEnterForeground()
                }
            }
            .store(in: &appLifecycleCancellables)
        
        // Observe when app enters background
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleAppDidEnterBackground()
                }
            }
            .store(in: &appLifecycleCancellables)
        
        // Observe when app will resign active (about to lose focus)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleAppWillResignActive()
                }
            }
            .store(in: &appLifecycleCancellables)
    }
    
    // MARK: - Push Notification Observers
    
    private func setupPushNotificationObservers() {
        // Observe when user taps a push notification
        NotificationCenter.default.publisher(for: .pushNotificationTapped)
            .sink { [weak self] notification in
                Task { @MainActor in
                    guard let userInfo = notification.userInfo,
                          let roomId = userInfo["roomId"] as? String,
                          let receivedAt = userInfo["receivedAt"] as? Date else {
                        print("[Push] ⚠️ Invalid notification userInfo")
                        return
                    }
                    
                    await self?.handlePushNotificationTap(roomId: roomId, receivedAt: receivedAt)
                }
            }
            .store(in: &appLifecycleCancellables)
        
        // Observe when a notification is received (to track it)
        NotificationCenter.default.publisher(for: .pushNotificationReceived)
            .sink { [weak self] notification in
                Task { @MainActor in
                    guard let userInfo = notification.userInfo,
                          let roomId = userInfo["roomId"] as? String,
                          let receivedAt = userInfo["receivedAt"] as? Date else {
                        print("[Push] ⚠️ Invalid notification userInfo")
                        return
                    }
                    
                    await self?.handlePushNotificationReceived(roomId: roomId, receivedAt: receivedAt)
                }
            }
            .store(in: &appLifecycleCancellables)
    }
    
    @MainActor
    private func handlePushNotificationReceived(roomId: String, receivedAt: Date) async {
        print("[Push] 📬 Tracking received notification for room: \(roomId.prefix(8))")
        
        // Find the session for this roomId
        guard let sessionIndex = sessions.firstIndex(where: { $0.roomId == roomId }) else {
            print("[Push] ⚠️ No session found for room: \(roomId.prefix(8))")
            return
        }
        
        // Add notification to the session
        let notification = SessionNotification(receivedAt: receivedAt)
        sessions[sessionIndex].notifications.append(notification)
        
        // Persist the change
        persistSessions()
        
        // Update badge count
        updateBadgeCount()
        
        print("[Push] ✅ Tracked notification for session: \(sessions[sessionIndex].displayName)")
    }
    
    @MainActor
    private func handlePushNotificationTap(roomId: String, receivedAt: Date) async {
        print("[Push] 📱 Notification tapped for room: \(roomId.prefix(8)) - just opening app")
        
        // Find the session for this roomId
        guard let sessionIndex = sessions.firstIndex(where: { $0.roomId == roomId }) else {
            print("[Push] ⚠️ No session found for room: \(roomId.prefix(8))")
            return
        }
        
        let session = sessions[sessionIndex]
        
        // Add this notification to history if not already tracked
        let alreadyTracked = session.notifications.contains { notification in
            // Check if we already have a notification within 5 seconds of this one
            abs(notification.receivedAt.timeIntervalSince(receivedAt)) < 5
        }
        
        if !alreadyTracked {
            let notification = SessionNotification(receivedAt: receivedAt)
            sessions[sessionIndex].notifications.append(notification)
            persistSessions()
        }
        
        // NO NAVIGATION - just open the app normally
        // User can manually navigate to SessionsView to see which session has notifications
        print("[Push] ✅ Notification tracked, app opened without auto-navigation")
    }
    
    @MainActor
    private func handlePushNotificationTap_OLD(roomId: String) async {
        print("[Push] 📱 Handling notification tap for room: \(roomId.prefix(8))")
        
        // If we're already in this room, just bring the app to foreground
        if self.roomId == roomId {
            print("[Push] ℹ️ Already in room \(roomId.prefix(8))")
            // Still trigger navigation in case user is on a different screen
            shouldNavigateToChat = true
            return
        }
        
        // If we're in a different room, leave it first
        if !self.roomId.isEmpty {
            print("[Push] ⚠️ Leaving current room \(self.roomId.prefix(8)) to join \(roomId.prefix(8))")
            leave(userInitiated: false)
            try? await Task.sleep(nanoseconds: 500_000_000) // Brief delay for cleanup
        }
        
        // IMPORTANT: Force a fresh WebSocket reconnection
        // When app comes from background, the old WebSocket connection might be stale
        // Even if connectionStatus shows .connected, the connection could be broken
        print("[Push] � Forcing fresh WebSocket reconnection for reliable join...")
        signaling.disconnect()
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms to ensure clean disconnect
        signaling.connect()
        
        // Wait for connection with timeout
        print("[Push] ⏳ Waiting for WebSocket connection...")
        for i in 0..<50 { // 5 second timeout (50 * 100ms)
            if connectionStatus == .connected {
                print("[Push] ✅ WebSocket connected (took \(i * 100)ms)")
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        if connectionStatus != .connected {
            print("[Push] ❌ Failed to connect to signaling server after 5s timeout")
            return
        }
        
        // Extra small delay to ensure clientId is properly set
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Join the room from the push notification
        print("[Push] 🚀 Joining room \(roomId.prefix(8))")
        joinRoom(roomId: roomId)
        
        // Trigger UI navigation to chat view
        shouldNavigateToChat = true
        print("[Push] � Triggering navigation to chat view")
    }
    
    private func handleAppBecameActive() async {
        print("📱 App became active")
        print("🔍 State check: roomId=\(roomId.isEmpty ? "empty" : String(roomId.prefix(8))), isP2PConnected=\(isP2PConnected), hadP2POnce=\(hadP2POnce)")
        print("🔍 wasInRoomBeforeDisconnect=\(wasInRoomBeforeDisconnect ?? "nil")")
        
        // Sync pending notifications from Notification Service Extension
        syncPendingNotifications()
        
        // Update badge count based on total unread notifications
        updateBadgeCount()
        
        // Clear notification center cards (but keep badge showing unread count)
        clearNotificationCenter()
        
        // Check if we're in a room but P2P is not connected, and we had P2P before
        // This covers the case where connection dropped while phone was locked/backgrounded
        if !roomId.isEmpty && !isP2PConnected && hadP2POnce {
            print("🔄 Detected stuck in waiting state - auto-rejoining room: \(roomId.prefix(8))...")
            let roomToRejoin = roomId
            
            // Leave first to clean up server state
            leave(userInitiated: false)
            // Wait a bit for leave to complete
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Reconnect signaling if needed
            if connectionStatus != .connected {
                print("🔌 Reconnecting signaling...")
                signaling.connect()
                // Wait for connection
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
            
            // Rejoin the room
            print("✅ Rejoining room: \(roomToRejoin.prefix(8))")
            joinRoom(roomId: roomToRejoin)
        } else if let savedRoomId = wasInRoomBeforeDisconnect, !savedRoomId.isEmpty {
            // Fallback: use saved room from explicit disconnect tracking
            print("🔄 App became active - auto-rejoining saved room: \(savedRoomId.prefix(8))...")
            wasInRoomBeforeDisconnect = nil
            
            // Leave first if we're somehow still in a room
            if !roomId.isEmpty {
                leave(userInitiated: false)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            // Reconnect signaling if needed
            if connectionStatus != .connected {
                signaling.connect()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            // Rejoin the room
            joinRoom(roomId: savedRoomId)
        } else {
            print("ℹ️ No auto-rejoin needed")
        }
    }
    
    private func handleAppWillResignActive() {
        print("📱 App will resign active")
        // Save current room if we're in one and P2P was established
        if !roomId.isEmpty && hadP2POnce {
            wasInRoomBeforeDisconnect = roomId
            print("💾 App will resign active - saved room: \(roomId.prefix(8))")
        } else {
            print("ℹ️ Not saving room (isEmpty=\(roomId.isEmpty), hadP2P=\(hadP2POnce))")
        }
    }
    
    private func handleAppDidEnterBackground() {
        print("📱 App entered background")
        // Save current room if we're in one
        if !roomId.isEmpty {
            wasInRoomBeforeDisconnect = roomId
            print("💾 Entered background - saved room: \(roomId.prefix(8))")
        }
    }
    
    private func handleAppWillEnterForeground() async {
        print("📱 App entering foreground")
        // This is called before didBecomeActive, so we'll let didBecomeActive handle the rejoin
        // But we can ensure signaling is reconnected here
        if connectionStatus != .connected {
            print("🔌 Reconnecting signaling on foreground...")
            signaling.connect()
            try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
        }
    }
    
    @objc private func handleKeyExchangeReceived(_ notification: Notification) {
        print("🔍 [DEBUG] handleKeyExchangeReceived called")
        print("🔍 [DEBUG] userInfo: \(notification.userInfo ?? [:])")
        
        guard let userInfo = notification.userInfo,
              let messageDict = userInfo["message"] as? [String: Any] else {
            print("⚠️ Invalid key_exchange message format: missing userInfo or message dict")
            print("🔍 [DEBUG] Notification object: \(String(describing: notification.object))")
            return
        }
        
        print("🔍 [DEBUG] messageDict: \(messageDict)")
        print("🔍 [DEBUG] messageDict keys: \(messageDict.keys)")
        
        guard let publicKeyBase64 = messageDict["publicKey"] as? String,
              let sessionId = messageDict["sessionId"] as? String else {
            print("⚠️ Invalid key_exchange message format: missing publicKey or sessionId")
            print("🔍 [DEBUG] publicKey: \(String(describing: messageDict["publicKey"]))")
            print("🔍 [DEBUG] sessionId: \(String(describing: messageDict["sessionId"]))")
            return
        }
        
        print("✅ [DEBUG] Received valid key_exchange: publicKey=\(publicKeyBase64.prefix(16))..., sessionId=\(sessionId)")
        
        // If we haven't generated our own keypair yet, queue this for later
        if keyExchangeHandler == nil {
            print("⏳ [DEBUG] Queueing peer public key until our keypair is ready")
            pendingPeerPublicKey = (publicKeyBase64, sessionId)
            return
        }
        
        Task { @MainActor in
            await handlePeerPublicKey(publicKeyBase64, sessionId: sessionId)
        }
    }
    
    @objc private func handleKeyExchangeCompleteReceived(_ notification: Notification) {
        print("🔍 [DEBUG] handleKeyExchangeCompleteReceived called")
        guard let userInfo = notification.userInfo,
              let messageDict = userInfo["message"] as? [String: Any],
              let sessionId = messageDict["sessionId"] as? String else {
            print("⚠️ Invalid key_exchange_complete message format")
            print("🔍 [DEBUG] userInfo: \(String(describing: notification.userInfo))")
            return
        }
        
        print("✅ [DEBUG] Initiator received key_exchange_complete for session: \(sessionId)")
        
        Task { @MainActor in
            // Initiator receives this, so pass isInitiator: true
            await finalizeKeyExchange(sessionId: sessionId, isInitiator: true)
        }
    }
    
    private func startKeyExchange(isInitiator: Bool) {
        guard !roomId.isEmpty else {
            print("⚠️ Cannot start key exchange: no room ID")
            return
        }
        
        // Check if we've already started key exchange for this session
        if keyExchangeInProgress {
            print("⚠️ Key exchange already in progress, skipping duplicate initiation")
            return
        }
        
        // Check if encryption is already ready (reconnection scenario)
        if isEncryptionReady {
            print("⚠️ Encryption already ready for this session, regenerating for security")
            // Wipe old keys and restart
            cleanupEncryption()
        }
        
        keyExchangeInProgress = true
        isEncryptionReady = false
        
        // Generate a deterministic UUID from roomId for Keychain storage
        // Both peers will use the same UUID since they share the same roomId
        // Convert roomId hex string to UUID by taking first 32 hex chars and formatting as UUID
        let roomIdPrefix = roomId.prefix(32)
        let uuidString = "\(roomIdPrefix.prefix(8))-\(roomIdPrefix.dropFirst(8).prefix(4))-\(roomIdPrefix.dropFirst(12).prefix(4))-\(roomIdPrefix.dropFirst(16).prefix(4))-\(roomIdPrefix.dropFirst(20).prefix(12))"
        let sessionKeyId = UUID(uuidString: uuidString) ?? UUID()
        currentSessionKeyId = sessionKeyId
        
        print("🔍 [DEBUG] Using sessionKeyId: \(sessionKeyId.uuidString.prefix(8)) for roomId: \(roomId.prefix(8))")
        
        do {
            // Generate our keypair
            let handler = KeyExchangeHandler()
            let publicKey = try handler.generateKeypair(sessionId: sessionKeyId)
            self.keyExchangeHandler = handler
            
            // Send our public key to peer via signaling
            let publicKeyBase64 = publicKey.rawRepresentation.base64EncodedString()
            signaling.send([
                "type": "key_exchange",
                "publicKey": publicKeyBase64,
                "sessionId": roomId
            ])
            
            // Initialize encryption state
            let state = EncryptionState()
            encryptionStates[roomId] = state
            
            print("✅ Key exchange initiated (isInitiator: \(isInitiator))")
            
            // Process any queued peer public key that arrived before we were ready
            if let pending = pendingPeerPublicKey {
                print("🔄 [DEBUG] Processing queued peer public key")
                pendingPeerPublicKey = nil
                Task { @MainActor in
                    await handlePeerPublicKey(pending.publicKey, sessionId: pending.sessionId)
                }
            }
            
        } catch {
            print("❌ Key exchange failed: \(error)")
            keyExchangeInProgress = false
            // Fallback: proceed without encryption (production should handle this better)
            createP2PConnectionAfterKeyExchange(isInitiator: isInitiator)
        }
    }
    
    private func handlePeerPublicKey(_ publicKeyBase64: String, sessionId: String) async {
        guard let peerPublicKeyData = Data(base64Encoded: publicKeyBase64) else {
            print("⚠️ Invalid base64 peer public key")
            return
        }
        
        guard encryptionStates[sessionId] != nil else {
            print("⚠️ No encryption state for session \(sessionId)")
            return
        }
        
        // Derive the same UUID from sessionId (roomId) that both peers use
        let roomIdPrefix = sessionId.prefix(32)
        let uuidString = "\(roomIdPrefix.prefix(8))-\(roomIdPrefix.dropFirst(8).prefix(4))-\(roomIdPrefix.dropFirst(12).prefix(4))-\(roomIdPrefix.dropFirst(16).prefix(4))-\(roomIdPrefix.dropFirst(20).prefix(12))"
        guard let sessionKeyId = UUID(uuidString: uuidString) else {
            print("⚠️ Failed to derive UUID from sessionId: \(sessionId)")
            return
        }
        
        print("🔍 [DEBUG] Derived sessionKeyId: \(sessionKeyId.uuidString.prefix(8)) from received sessionId: \(sessionId.prefix(8))")
        
        // Update currentSessionKeyId to match what we derived
        currentSessionKeyId = sessionKeyId
        
        do {
            guard let handler = keyExchangeHandler else {
                throw EncryptionError.keyExchangeFailed("Key exchange handler not initialized")
            }
            
            // Validate and reconstruct peer public key
            guard peerPublicKeyData.count == EncryptionConstants.publicKeySize else {
                throw EncryptionError.invalidPublicKeyLength
            }
            
            let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyData)
            
            print("🔍 [DEBUG] About to derive session key with:")
            print("  - Peer public key: \(publicKeyBase64.prefix(16))...")
            print("  - sessionKeyId: \(sessionKeyId.uuidString.prefix(8))")
            
            // Derive session key using ECDH + HKDF
            let derivedKey = try handler.deriveSessionKey(
                peerPublicKey: peerPublicKey,
                sessionId: sessionKeyId
            )
            
            let derivedKeyBytes = derivedKey.withUnsafeBytes { bytes in
                Data(bytes).prefix(8).base64EncodedString()
            }
            print("🔍 [DEBUG] Derived session key: \(derivedKeyBytes)...")
            
            // DIAGNOSTIC: Retrieve and verify the stored session key
            if let storedKey = try? encryptionKeychain.getKey(for: .sessionKey, sessionId: sessionKeyId) {
                let storedKeyBytes = storedKey.prefix(8).base64EncodedString()
                print("🔍 [DEBUG] Verified stored session key: \(storedKeyBytes)...")
            } else {
                print("⚠️ [DEBUG] Failed to retrieve stored session key!")
            }
            
            // Update state
            var state = encryptionStates[sessionId]!
            state.keyExchangeComplete = true
            encryptionStates[sessionId] = state
            
            // Determine role: Use stored original role if available, otherwise use server-assigned
            let storedRole = sessions.first(where: { $0.roomId == self.roomId })?.wasOriginalInitiator
            let isInitiator: Bool
            
            if let stored = storedRole {
                // Use persisted original role for consistency across rejoins
                isInitiator = stored
                print("🔍 [DEBUG] Using STORED original role: \(isInitiator ? "INITIATOR" : "RESPONDER")")
            } else if let serverAssigned = serverAssignedIsInitiator {
                // First time joining - use server assignment
                isInitiator = serverAssigned
                print("🔍 [DEBUG] Using SERVER assigned role: \(isInitiator ? "INITIATOR" : "RESPONDER")")
            } else {
                // Fallback (shouldn't happen)
                isInitiator = (self.roomId == sessionId && hadP2POnce == false)
                print("🔍 [DEBUG] Using FALLBACK role: \(isInitiator ? "INITIATOR" : "RESPONDER")")
            }
            
            print("🔍 [DEBUG] Role determination: isInitiator=\(isInitiator), storedRole=\(String(describing: storedRole)), serverAssigned=\(String(describing: serverAssignedIsInitiator)), roomId=\(self.roomId), sessionId=\(sessionId), hadP2POnce=\(hadP2POnce)")
            
            // If we're the responder, send key_exchange_complete
            if !isInitiator {
                print("🔍 [DEBUG] RESPONDER: Sending key_exchange_complete to initiator")
                print("📤 [DEBUG] Sending key_exchange_complete: sessionId=\(sessionId.prefix(8))...")
                signaling.send([
                    "type": "key_exchange_complete",
                    "sessionId": sessionId
                ])
                // Responder can finalize immediately
                await finalizeKeyExchange(sessionId: sessionId, isInitiator: false)
            } else {
                print("🔍 [DEBUG] INITIATOR: Waiting for key_exchange_complete from responder")
            }
            
            print("✅ Session key derived successfully")
            
        } catch {
            print("❌ Failed to derive session key: \(error)")
            keyExchangeInProgress = false
        }
    }
    
    private func finalizeKeyExchange(sessionId: String, isInitiator: Bool) async {
        print("🔍 [DEBUG] finalizeKeyExchange called: sessionId=\(sessionId), isInitiator=\(isInitiator)")
        
        guard var state = encryptionStates[sessionId] else {
            print("⚠️ No encryption state for session \(sessionId)")
            return
        }
        
        guard let sessionKeyId = currentSessionKeyId else {
            print("⚠️ No session key ID available")
            return
        }
        
        // Verify session key exists in Keychain
        guard let _ = try? encryptionKeychain.getKey(for: .sessionKey, sessionId: sessionKeyId) else {
            print("⚠️ Session key not found in Keychain")
            return
        }
        
        // Update state
        state.keyExchangeComplete = true
        encryptionStates[sessionId] = state
        
        keyExchangeInProgress = false
        isEncryptionReady = true
        
        print("✅ Encryption ready (session: \(sessionId))")
        
        // Update session model with encryption timestamp
        if let activeId = activeSessionId,
           let idx = sessions.firstIndex(where: { $0.id == activeId }) {
            sessions[idx].keyExchangeCompletedAt = Date()
            persistSessions()
        }
        
        // Now create P2P connection
        createP2PConnectionAfterKeyExchange(isInitiator: isInitiator)
    }
    
    private func createP2PConnectionAfterKeyExchange(isInitiator: Bool) {
        print("🔍 [DEBUG] createP2PConnectionAfterKeyExchange: isInitiator=\(isInitiator)")
        
        if isInitiator {
            // Initiator creates PeerConnection and sends offer
            pcm.createPeerConnection(isInitiator: true, customHost: ServerConfig.shared.host)
            print("🔍 [DEBUG] Initiator creating WebRTC offer in 1 second...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("🔍 [DEBUG] Initiator creating WebRTC offer NOW")
                self.pcm.createOffer { sdp in
                    guard let sdp = sdp else {
                        print("⚠️ Failed to create WebRTC offer")
                        return
                    }
                    print("✅ [DEBUG] Sending WebRTC offer via signaling")
                    self.signaling.send(["type": "webrtc_offer", "sdp": sdp.sdp])
                }
            }
        } else {
            // Responder waits for offer (PeerConnection will be created when offer arrives)
            print("🔍 [DEBUG] Responder waiting for WebRTC offer from initiator (will create PeerConnection on offer receipt)")
        }
    }
    
    private func cleanupEncryption() {
        let sessionId = roomId
        
        // Delete all keys from Keychain for this session
        if let keyId = currentSessionKeyId {
            do {
                try encryptionKeychain.deleteKeys(for: keyId)
                print("✅ Encryption keys wiped for session: \(sessionId)")
            } catch {
                print("⚠️ Failed to delete keys: \(error)")
            }
        }
        
        // Clear in-memory state
        keyExchangeHandler = nil
        currentSessionKeyId = nil
        pendingPeerPublicKey = nil
        if !sessionId.isEmpty {
            encryptionStates.removeValue(forKey: sessionId)
        }
        
        isEncryptionReady = false
        keyExchangeInProgress = false
    }

    // MARK: - P2P Connection Handling (Legacy)

    // Internal
    private func handleServerMessage(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "room_joined":
            if let roomId = json["roomId"] as? String { self.roomId = roomId }
            // Store server-assigned initiator role
            if let isInitiator = json["isInitiator"] as? Bool {
                serverAssignedIsInitiator = isInitiator
                print("🔍 [DEBUG] Server assigned role: \(isInitiator ? "INITIATOR" : "RESPONDER")")
                
                // Store this as the original role for the active session if not already set
                if let activeId = activeSessionId, let idx = sessions.firstIndex(where: { $0.id == activeId }) {
                    if sessions[idx].wasOriginalInitiator == nil {
                        sessions[idx].wasOriginalInitiator = isInitiator
                        persistSessions()
                        print("🔍 [DEBUG] Stored original role for session: wasOriginalInitiator=\(isInitiator)")
                    } else {
                        print("🔍 [DEBUG] Using stored original role: wasOriginalInitiator=\(sessions[idx].wasOriginalInitiator!)")
                    }
                }
            }
            // Reset per-room P2P flag; initial connect shouldn't create a system message
            hadP2POnce = false
        case "room_ready":
            let isInitiator = json["isInitiator"] as? Bool ?? false
            // Only establish P2P connection if ChatView is active
            if isChatViewActive {
                handleRoomReady(isInitiator: isInitiator)
            } else {
                // Queue for later processing when ChatView appears
                pendingRoomReadyIsInitiator = isInitiator
            }
        case "webrtc_offer":
            // Only process WebRTC offer if ChatView is active
            guard isChatViewActive else { return }
            guard let sdp = json["sdp"] as? String else { return }
            let offer = RTCSessionDescription(type: .offer, sdp: sdp)
            if self.pcm.pc == nil { self.pcm.createPeerConnection(isInitiator: false, customHost: ServerConfig.shared.host) }
            self.pcm.setRemoteOfferAndCreateAnswer(offer) { answer in
                guard let answer = answer else { return }
                self.signaling.send(["type": "webrtc_answer", "sdp": answer.sdp])
            }
        case "webrtc_answer":
            // Only process if we have a peer connection (means we're the initiator who sent offer)
            guard pcm.pc != nil else { return }
            guard let sdp = json["sdp"] as? String else { return }
            let answer = RTCSessionDescription(type: .answer, sdp: sdp)
            self.pcm.setRemoteAnswer(answer) { _ in }
        case "ice_candidate":
            // Only process ICE candidates if we have a peer connection
            guard pcm.pc != nil else { return }
            guard let c = json["candidate"] as? [String: Any],
                  let sdp = c["candidate"] as? String,
                  let idx = c["sdpMLineIndex"] as? Int32,
                  let mid = c["sdpMid"] as? String else { return }
            self.pcm.addRemoteCandidate(RTCIceCandidate(sdp: sdp, sdpMLineIndex: idx, sdpMid: mid))
        case "peer_disconnected", "peer_left":
            // Allow WebRTC to teardown without blocking UI
            self.isP2PConnected = false
            self.connectionPath = .unknown
            self.pcm.close()
            // IMPORTANT: Do NOT clear roomId here. We still consider ourselves logically in the room
            // until the user explicitly leaves. Clearing it prevented a later explicit leave() call
            // from sending the leave_room message (guard !roomId.isEmpty early-return), causing the
            // server to keep this client in the room and auto-reconnect when the other peer rejoined.
            // The UI can distinguish waiting state via isP2PConnected/remotePeerPresent.
            self.remotePeerPresent = false
            
            // Wipe encryption keys when peer leaves (E2EE security best practice)
            cleanupEncryption()
            isEncryptionReady = false
            keyExchangeInProgress = false
            
            self.messages.append(ChatMessage(text: "Client left the room", timestamp: Date(), isFromSelf: false, isSystem: true))
        case "left_room":
            self.isAwaitingLeaveAck = false
        case "error":
            if let msg = json["error"] as? String { print("Server error: \(msg)") }
        default: break
        }
    }
}

extension ChatManager: SignalingClientDelegate {
    func signalingConnected(clientId: String) {
        self.clientId = clientId
        connectionStatus = .connected
        isOnline = true
    // When WS connects, also validate backend state (pendings/rooms)
    pollPendingAndValidateRooms()
        // Previous behavior auto-joined pending room. Now we only auto-join if the user was online when initiating.
        if let pending = pendingJoinRoomId {
            pendingJoinRoomId = nil
            joinRoom(roomId: pending)
        }
    }
    func signalingMessage(_ json: [String : Any]) { handleServerMessage(json) }
    func signalingClosed() {
        connectionStatus = .disconnected
        isOnline = false
    }
}

extension ChatManager: PeerConnectionManagerDelegate {
    func pcmDidGenerateIce(_ candidate: RTCIceCandidate) {
        signaling.send(["type": "ice_candidate", "candidate": [
            "candidate": candidate.sdp,
            "sdpMLineIndex": candidate.sdpMLineIndex,
            "sdpMid": candidate.sdpMid ?? ""
        ]])
    }
    func pcmIceStateChanged(connected: Bool) {
        let was = isP2PConnected
        isP2PConnected = connected
        if connected && was == false {
            messages.append(ChatMessage(text: "Client joined the room", timestamp: Date(), isFromSelf: false, isSystem: true))
            hadP2POnce = true
            // When P2P comes up for created session, consider as accepted
            markActiveSessionAccepted()
            classifyConnectionPath()
            // Retry classification after 1.5s if still unknown (stats may not be ready immediately)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self, self.connectionPath == .unknown else { return }
                self.classifyConnectionPath()
            }
            remotePeerPresent = true
        } else if !connected && was == true {
            // P2P connection dropped - clean up encryption keys for security
            print("🔒 P2P connection lost - wiping encryption keys")
            cleanupEncryption()
            connectionPath = .unknown
            
            // Save room for auto-rejoin when app returns to foreground
            if !roomId.isEmpty {
                wasInRoomBeforeDisconnect = roomId
                print("💾 P2P dropped - saved room for auto-rejoin: \(roomId.prefix(8))")
            }
        }
    }
    
    func pcmDidReceiveMessage(_ text: String) {
        // Legacy text message handler (deprecated - kept for backwards compatibility)
        messages.append(ChatMessage(text: text, timestamp: Date(), isFromSelf: false))
        // Update activity for active session when receiving messages
        if let sessionId = activeSessionId {
            updateSessionActivity(sessionId)
        }
    }
    
    func pcmDidReceiveData(_ data: Data) {
        // New binary encrypted message handler
        guard isEncryptionReady else {
            print("⚠️ Received encrypted data but encryption not ready")
            return
        }
        
        guard var state = encryptionStates[roomId],
              let sessionKeyId = currentSessionKeyId else {
            print("⚠️ No encryption state for current room")
            return
        }
        
        do {
            // LOG: Show raw encrypted data
            let encryptedDataHex = data.prefix(64).map { String(format: "%02x", $0) }.joined()
            let encryptedDataBase64 = data.prefix(128).base64EncodedString()
            print("📦 [E2EE] Received encrypted data (\(data.count) bytes)")
            print("   Hex (first 64 bytes): \(encryptedDataHex)")
            print("   Base64 (first 128 bytes): \(encryptedDataBase64)")
            
            // Deserialize wire format
            let decoder = JSONDecoder()
            let wireFormat = try decoder.decode(MessageWireFormat.self, from: data)
            
            // Validate protocol version
            guard wireFormat.v == 1 else {
                print("⚠️ Unsupported protocol version: \(wireFormat.v)")
                return
            }
            
            // Get session key from Keychain
            guard let sessionKeyData = try encryptionKeychain.getKey(for: .sessionKey, sessionId: sessionKeyId),
                  sessionKeyData.count == EncryptionConstants.sessionKeySize else {
                throw EncryptionError.sessionKeyNotFound
            }
            let sessionKey = SymmetricKey(data: sessionKeyData)
            
            // DIAGNOSTIC: Log key being used for decryption
            let keyBytes = sessionKeyData.prefix(8).base64EncodedString()
            print("🔓 [DEBUG] Decrypting with session key: \(keyBytes)..., counter: \(wireFormat.c)")
            
            // Decrypt the message
            let plaintext = try messageEncryptor.decrypt(
                wireFormat,
                sessionKey: sessionKey,
                direction: .send  // Use .send to match the sender's encryption
            )
            
            // LOG: Show decrypted plaintext
            print("✅ [E2EE] Decrypted message: \"\(plaintext)\"")
            
            // Update receive counter
            state.receiveCounter = max(state.receiveCounter, wireFormat.c + 1)
            encryptionStates[roomId] = state
            
            // Calculate expiration date based on current retention policy
            let expiresAt = currentRetentionPolicy.expirationDate(from: Date())
            
            // Check if message is a retention policy sync message
            if let policyMessage = RetentionPolicyMessage.fromJSONString(plaintext) {
                print("🔄 [Retention] Received policy sync: \(policyMessage.policy.displayName)")
                peerRetentionPolicy = policyMessage.policy
                // Don't add to messages list - this is a control message
                return
            }
            
            // Check if message is a location (JSON format)
            if let locationData = LocationData.fromJSONString(plaintext) {
                // Display as location message
                var msg = ChatMessage(text: "", timestamp: Date(), isFromSelf: false)
                msg.locationData = locationData
                msg.expiresAt = expiresAt
                messages.append(msg)
                print("📍 Received location: \(locationData.latitude), \(locationData.longitude)")
            } else if let voiceData = VoiceData.fromJSONString(plaintext) {
                // Display as voice message
                var msg = ChatMessage(text: "", timestamp: Date(), isFromSelf: false)
                msg.voiceData = voiceData
                msg.expiresAt = expiresAt
                messages.append(msg)
                print("🎤 Received voice message: \(voiceData.duration)s")
            } else {
                // Display as text message
                messages.append(ChatMessage(text: plaintext, timestamp: Date(), isFromSelf: false, expiresAt: expiresAt))
            }
            
            // Update activity for active session
            if let sessionId = activeSessionId {
                updateSessionActivity(sessionId)
                
                // Save messages if retention policy is not noStorage
                if currentRetentionPolicy != .noStorage {
                    do {
                        try messageStorage.saveMessages(messages, for: sessionId)
                    } catch {
                        print("[ChatManager] ⚠️ Failed to save messages: \(error)")
                    }
                }
            }
            
        } catch {
            print("❌ Failed to decrypt message: \(error)")
        }
    }
}

// MARK: - Connection Path Classification
extension ChatManager {
    enum ConnectionPath: Equatable {
        case directLAN          // host↔host on same network
        case directReflexive    // srflx / host mix (NAT hole-punched)
        case relayed(server: String?) // TURN relay (server domain/ip if known)
        case possiblyVPN        // Mixed or unusual candidates suggesting VPN
        case unknown

        var displayName: String {
            switch self {
            case .directLAN: return "Direct LAN"
            case .directReflexive: return "Direct (NAT)"
            case .relayed(let server): return server.map { "Relayed via \($0)" } ?? "Relayed"
            case .possiblyVPN: return "Direct (Possibly VPN)"
            case .unknown: return "Determining…"
            }
        }
        var shortLabel: String {
            switch self {
            case .directLAN: return "LAN"
            case .directReflexive: return "NAT"
            case .relayed: return "RELAY"
            case .possiblyVPN: return "VPN?"
            case .unknown: return "…"
            }
        }
        var icon: String {
            switch self {
            case .directLAN: return "wifi"
            case .directReflexive: return "arrow.left.and.right"
            case .relayed: return "cloud"
            case .possiblyVPN: return "network.badge.shield.half.filled"
            case .unknown: return "questionmark"
            }
        }
        var color: String {
            switch self {
            case .directLAN: return "green"
            case .directReflexive: return "teal"
            case .relayed: return "orange"
            case .possiblyVPN: return "purple"
            case .unknown: return "gray"
            }
        }
    }

    private func classifyConnectionPath() {
        // Fetch stats immediately, then classify
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.pcm.fetchStats { report in
                // Locate selected candidate pair id
                var pairValues: [String: Any]? = nil
                var localCandidateId: String? = nil
                var remoteCandidateId: String? = nil
                for (_, stat) in report.statistics {
                    if stat.type == "transport" { // transport may reference candidate pair
                        if let sel = stat.values["selectedCandidatePairId"] as? String,
                           let pair = report.statistics[sel]?.values { pairValues = pair }
                    }
                    if stat.type == "candidate-pair" { // fallback
                        if let nominated = stat.values["nominated"] as? String, nominated == "true" {
                            pairValues = stat.values
                        }
                    }
                }
                if let pv = pairValues {
                    localCandidateId = pv["localCandidateId"] as? String
                    remoteCandidateId = pv["remoteCandidateId"] as? String
                }
                func candidateInfo(_ id: String?) -> (type: String?, ip: String?, url: String?) {
                    guard let id = id, let stat = report.statistics[id] else { return (nil,nil,nil) }
                    let type = stat.values["candidateType"] as? String
                    let ip = (stat.values["ip"] as? String) ?? (stat.values["address"] as? String)
                    let url = stat.values["url"] as? String
                    return (type, ip, url)
                }
                let local = candidateInfo(localCandidateId)
                let remote = candidateInfo(remoteCandidateId)
                let allTypes = [local.type, remote.type].compactMap { $0 }
                
                // Determine connection path
                let path: ConnectionPath
                if allTypes.contains("relay") {
                    // Try to extract server host from url (turn:domain:port)
                    let server = (local.url ?? remote.url)?.split(separator: ":").dropFirst().first.map { String($0) }
                    path = .relayed(server: server)
                } else if allTypes.allSatisfy({ $0 == "host" }) {
                    path = .directLAN
                } else if allTypes.allSatisfy({ $0 == "host" || $0 == "srflx" }) {
                    path = .directReflexive
                } else if allTypes.isEmpty {
                    // No candidate types found - stats might not be ready yet
                    path = .unknown
                } else {
                    // Mixed or unusual candidates (e.g., one side has srflx, other has prflx)
                    // This often indicates VPN or unusual network configuration
                    path = .possiblyVPN
                }
                
                // Update on main thread
                DispatchQueue.main.async {
                    self.connectionPath = path
                }
            }
        }
    }
}

// MARK: - Room existence status (avoid false closure offline)
extension ChatManager {
    private enum RoomStatusResult { case exists, notFound, unreachable }

    private func getRoomStatus(_ roomId: String) async -> RoomStatusResult {
        // If offline, treat as unreachable immediately
        guard connectionStatus == .connected else { return .unreachable }
        guard var comps = URLComponents(url: apiBase.appendingPathComponent("/api/rooms"), resolvingAgainstBaseURL: false) else { return .unreachable }
        comps.queryItems = [URLQueryItem(name: "roomid", value: roomId)]
        guard let url = comps.url else { return .unreachable }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse else { return .unreachable }
            if http.statusCode == 200 {
                // Basic validation that payload has expected keys
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["client1"] != nil {
                    return .exists
                } else {
                    return .exists // Consider 200 as exists even if parsing partial
                }
            } else if http.statusCode == 404 {
                return .notFound
            } else {
                return .unreachable
            }
        } catch {
            return .unreachable
        }
    }
}

// MARK: - Message Retention Policy
extension ChatManager {
    
    /// Update retention policy for current session and sync with peer
    func updateRetentionPolicy(_ policy: MessageRetentionPolicy) {
        guard isEncryptionReady else {
            print("⚠️ [Retention] Cannot update policy - encryption not ready")
            return
        }
        
        currentRetentionPolicy = policy
        print("🔄 [Retention] Updated local policy to: \(policy.displayName)")
        
        // Update expiration dates for existing messages
        updateMessageExpiration()
        
        // Send policy update to peer via E2EE
        syncRetentionPolicyWithPeer(policy)
        
        // If switching to noStorage, delete stored messages
        if policy == .noStorage, let sessionId = activeSessionId {
            try? messageStorage.deleteMessages(for: sessionId)
            print("🗑️ [Retention] Deleted stored messages (switched to noStorage)")
        }
        
        // If switching to storage mode, save current messages
        if policy != .noStorage, let sessionId = activeSessionId {
            do {
                try messageStorage.saveMessages(messages, for: sessionId)
                print("💾 [Retention] Saved current messages (switched to storage mode)")
            } catch {
                print("⚠️ [Retention] Failed to save messages: \(error)")
            }
        }
    }
    
    /// Sync retention policy with peer over E2EE channel
    private func syncRetentionPolicyWithPeer(_ policy: MessageRetentionPolicy) {
        guard isP2PConnected, isEncryptionReady else {
            print("⚠️ [Retention] Cannot sync - not connected or encryption not ready")
            return
        }
        
        guard var state = encryptionStates[roomId],
              let sessionKeyId = currentSessionKeyId else {
            print("⚠️ [Retention] No encryption state for current room")
            return
        }
        
        let policyMessage = RetentionPolicyMessage(policy: policy, timestamp: Date())
        
        guard let plaintext = policyMessage.toJSONString() else {
            print("⚠️ [Retention] Failed to serialize policy message")
            return
        }
        
        do {
            // Get session key from Keychain
            guard let sessionKeyData = try encryptionKeychain.getKey(for: .sessionKey, sessionId: sessionKeyId),
                  sessionKeyData.count == EncryptionConstants.sessionKeySize else {
                throw EncryptionError.sessionKeyNotFound
            }
            let sessionKey = SymmetricKey(data: sessionKeyData)
            
            // Increment send counter
            let counter = state.sendCounter
            state.sendCounter += 1
            encryptionStates[roomId] = state
            
            // Encrypt the policy message
            let wireFormat = try messageEncryptor.encrypt(
                plaintext,
                sessionKey: sessionKey,
                counter: counter,
                direction: .send
            )
            
            // Serialize to JSON
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(wireFormat)
            
            // Send encrypted binary data over DataChannel
            let ok = pcm.sendData(jsonData)
            if ok {
                print("✅ [Retention] Sent policy sync to peer: \(policy.displayName)")
            } else {
                print("❌ [Retention] Failed to send policy sync")
            }
        } catch {
            print("❌ [Retention] Failed to encrypt policy sync: \(error)")
        }
    }
    
    /// Update expiration dates for all existing messages based on current policy
    private func updateMessageExpiration() {
        let now = Date()
        messages = messages.map { message in
            var updated = message
            // For existing messages, calculate expiration from their original timestamp
            updated.expiresAt = currentRetentionPolicy.expirationDate(from: message.timestamp)
            return updated
        }
        
        // Save updated messages if not in noStorage mode
        if currentRetentionPolicy != .noStorage, let sessionId = activeSessionId {
            do {
                try messageStorage.saveMessages(messages, for: sessionId)
            } catch {
                print("⚠️ [Retention] Failed to save updated messages: \(error)")
            }
        }
    }
    
    /// Delete all messages in current session
    func deleteAllMessages() {
        messages.removeAll()
        
        if let sessionId = activeSessionId {
            try? messageStorage.deleteMessages(for: sessionId)
            print("🗑️ [Retention] Deleted all messages for current session")
        }
    }
    
    /// Setup timer for automatic cleanup of expired messages
    private func setupRetentionCleanupTimer() {
        // Run cleanup every 5 minutes
        expirationCleanupTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.cleanupExpiredMessages()
        }
        
        // Also run cleanup on app becoming active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cleanupExpiredMessages()
        }
    }
    
    /// Remove expired messages from memory and storage
    private func cleanupExpiredMessages() {
        let originalCount = messages.count
        messages.removeAll { $0.isExpired }
        
        if messages.count != originalCount {
            print("🗑️ [Retention] Cleaned \(originalCount - messages.count) expired messages from memory")
            
            // Save cleaned messages if not in noStorage mode
            if currentRetentionPolicy != .noStorage, let sessionId = activeSessionId {
                do {
                    try messageStorage.saveMessages(messages, for: sessionId)
                } catch {
                    print("⚠️ [Retention] Failed to save cleaned messages: \(error)")
                }
            }
        }
        
        // Also run storage-wide cleanup
        messageStorage.cleanupExpiredMessages()
    }
}
