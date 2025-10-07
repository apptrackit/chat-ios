//
//  ChatManager.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/12/25.
//

import Foundation
import WebRTC
import Combine

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

    // Components (dynamic server config)
    private var signaling: SignalingClient
    private var apiBase: URL { URL(string: "https://\(ServerConfig.shared.host)")! }
    private let pcm = PeerConnectionManager()

    // State
    private var clientId: String?
    private var isAwaitingLeaveAck = false
    private var pendingJoinRoomId: String?
    private var suppressReconnectOnce = false
    private var hadP2POnce = false
    // Deep link join waiting confirmation
    @Published var pendingDeepLinkCode: String? = nil

    override init() {
    self.signaling = SignalingClient(serverURL: "wss://\(ServerConfig.shared.host)")
    super.init()
    signaling.delegate = self
        pcm.delegate = self
        loadSessions()
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
        let ok = pcm.send(text)
        if ok { messages.append(ChatMessage(text: text, timestamp: Date(), isFromSelf: true)) }
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
        }
    }

    func closeActiveSession() {
        guard let id = activeSessionId, let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].status = .closed
        activeSessionId = nil
    // If room exists, call backend delete
    if let rid = sessions[idx].roomId { Task { await deleteRoomOnServer(roomId: rid) } }
    persistSessions()
    }

    func selectSession(_ session: ChatSession) {
        activeSessionId = session.id
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

    // Internal
    private func handleServerMessage(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "room_joined":
            if let roomId = json["roomId"] as? String { self.roomId = roomId }
            // Reset per-room P2P flag; initial connect shouldn't create a system message
            hadP2POnce = false
        case "room_ready":
            let isInitiator = json["isInitiator"] as? Bool ?? false
            pcm.createPeerConnection(isInitiator: isInitiator, customHost: ServerConfig.shared.host)
            if isInitiator {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.pcm.createOffer { sdp in
                        guard let sdp = sdp else { return }
                        self.signaling.send(["type": "webrtc_offer", "sdp": sdp.sdp])
                    }
                }
            }
        case "webrtc_offer":
            guard let sdp = json["sdp"] as? String else { return }
            let offer = RTCSessionDescription(type: .offer, sdp: sdp)
            if self.pcm.pc == nil { self.pcm.createPeerConnection(isInitiator: false, customHost: ServerConfig.shared.host) }
            self.pcm.setRemoteOfferAndCreateAnswer(offer) { answer in
                guard let answer = answer else { return }
                self.signaling.send(["type": "webrtc_answer", "sdp": answer.sdp])
            }
        case "webrtc_answer":
            guard let sdp = json["sdp"] as? String else { return }
            let answer = RTCSessionDescription(type: .answer, sdp: sdp)
            self.pcm.setRemoteAnswer(answer) { _ in }
        case "ice_candidate":
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
        messages.append(ChatMessage(text: text, timestamp: Date(), isFromSelf: false))
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
