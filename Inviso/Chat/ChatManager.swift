//
//  ChatManager.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/12/25.
//

import Foundation
import WebRTC
import Combine
import CryptoKit

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
    
    // Encryption (E2EE)
    @Published var isEncryptionReady: Bool = false // True when key exchange completes and encryption is active
    @Published var keyExchangeInProgress: Bool = false // True during key negotiation

    // Components (dynamic server config)
    private var signaling: SignalingClient
    private var apiBase: URL { URL(string: "https://\(ServerConfig.shared.host)")! }
    private let pcm = PeerConnectionManager()
    
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

    override init() {
    self.signaling = SignalingClient(serverURL: "wss://\(ServerConfig.shared.host)")
    super.init()
    signaling.delegate = self
        pcm.delegate = self
        loadSessions()
        setupKeyExchangeObservers()
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
        // Update activity for the session being joined
        if let sessionId = sessions.first(where: { $0.roomId == roomId })?.id {
            updateSessionActivity(sessionId)
        }
        signaling.send(["type": "join_room", "roomId": roomId])
    }

    func leave(userInitiated: Bool = false) {
        if userInitiated { suppressReconnectOnce = true }
        guard !roomId.isEmpty else { return }
    messages.removeAll()
        // Stop P2P first to avoid any renegotiation or events during leave.
        pcm.close()
        isP2PConnected = false
    remotePeerPresent = false
        
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
            
            // Send encrypted binary data over DataChannel
            let ok = pcm.sendData(jsonData)
            if ok {
                messages.append(ChatMessage(text: text, timestamp: Date(), isFromSelf: true))
                // Update activity for active session
                if let sessionId = activeSessionId {
                    updateSessionActivity(sessionId)
                }
            }
        } catch {
            print("❌ Failed to encrypt message: \(error)")
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
            // If already accepted and have roomId, join room automatically
            if let rid = existing.roomId { joinRoom(roomId: rid) }
            return
        }
        // Otherwise attempt accept flow
        Task { [weak self] in
            guard let self = self else { return }
            if let result = await self.acceptJoinCode(code) {
                let session = self.addAcceptedSession(name: nil, code: code, roomId: result.roomId, ephemeralId: result.ephemeralId, isCreatedByMe: false)
                self.joinRoom(roomId: result.roomId)
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
            // If already accepted and have roomId, join room automatically
            if let rid = existing.roomId { joinRoom(roomId: rid) }
            return true
        }
        
        // Otherwise attempt accept flow
        if let result = await acceptJoinCode(code) {
            let session = addAcceptedSession(name: nil, code: code, roomId: result.roomId, ephemeralId: result.ephemeralId, isCreatedByMe: false)
            joinRoom(roomId: result.roomId)
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
            sessions[idx].status = .accepted
            // Set first connected timestamp if not already set
            if sessions[idx].firstConnectedAt == nil {
                sessions[idx].firstConnectedAt = Date()
            }
            persistSessions()
        }
    }

    func closeActiveSession() {
        guard let id = activeSessionId, let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].status = .closed
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

    /// Create and persist an accepted session (used for client2 joining by code, or when we already have roomId)
    @discardableResult
    func addAcceptedSession(name: String?, code: String, roomId: String, ephemeralId: String, isCreatedByMe: Bool) -> ChatSession {
        let s = ChatSession(name: name, code: code, roomId: roomId, createdAt: Date(), expiresAt: nil, status: .accepted, isCreatedByMe: isCreatedByMe, ephemeralDeviceId: ephemeralId)
        sessions.insert(s, at: 0)
        activeSessionId = s.id
        persistSessions()
        return s
    }

    // MARK: - Backend REST integration
    private func createPendingOnServer(session: ChatSession, originalMinutes: Int) async {
        let joinid = session.code
        // Use original minutes value directly (more accurate than recalculating)
        let expiresInSeconds = originalMinutes * 60
        let client1 = session.ephemeralDeviceId // Use ephemeral ID for privacy
        var req = URLRequest(url: apiBase.appendingPathComponent("/api/rooms"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["joinid": joinid, "expiresInSeconds": expiresInSeconds, "client1": client1]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do { _ = try await URLSession.shared.data(for: req) } catch { print("createPending error: \(error)") }
    }

    func acceptJoinCode(_ code: String) async -> (roomId: String, ephemeralId: String)? {
        let client2 = UUID().uuidString // Generate new ephemeral ID for this session
        var req = URLRequest(url: apiBase.appendingPathComponent("/api/rooms/accept"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["joinid": code, "client2": client2])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return nil }
            if http.statusCode == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rid = json["roomid"] as? String { 
                return (rid, client2)
            }
            if http.statusCode == 404 || http.statusCode == 409 { return nil }
        } catch { print("acceptJoinCode error: \(error)") }
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
                        sessions[i].status = .accepted
                        sessions[i].roomId = roomId
                        // Set first connected timestamp if not already set
                        if sessions[i].firstConnectedAt == nil {
                            sessions[i].firstConnectedAt = Date()
                        }
                        persistSessions()
                    case .expired:
                        sessions[i].status = .expired
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
                        sessions[i].status = .closed
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
    private func persistSessions() {
        do {
            let data = try JSONEncoder().encode(sessions)
            UserDefaults.standard.set(data, forKey: storeKey)
        } catch {
            print("persistSessions error: \(error)")
        }
    }
    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: storeKey), let arr = try? JSONDecoder().decode([ChatSession].self, from: data) {
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
            
            // Determine role based on server-assigned value (fallback to old logic)
            let isInitiator = serverAssignedIsInitiator ?? (self.roomId == sessionId && hadP2POnce == false)
            
            print("🔍 [DEBUG] Role determination: isInitiator=\(isInitiator), serverAssigned=\(String(describing: serverAssignedIsInitiator)), roomId=\(self.roomId), sessionId=\(sessionId), hadP2POnce=\(hadP2POnce)")
            
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
            
            // Update receive counter
            state.receiveCounter = max(state.receiveCounter, wireFormat.c + 1)
            encryptionStates[roomId] = state
            
            // Display decrypted message
            messages.append(ChatMessage(text: plaintext, timestamp: Date(), isFromSelf: false))
            
            // Update activity for active session
            if let sessionId = activeSessionId {
                updateSessionActivity(sessionId)
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
