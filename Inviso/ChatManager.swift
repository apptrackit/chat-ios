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
    @Published var isEphemeral: Bool = false // Manual Room mode: don't keep history
    // Sessions (frontend)
    @Published var sessions: [ChatSession] = []
    @Published var activeSessionId: UUID?

    // Components
    private let signaling = SignalingClient(serverURL: "wss://chat.ballabotond.com")
    private let apiBase = URL(string: "https://chat.ballabotond.com")!
    private let pcm = PeerConnectionManager()

    // State
    private var clientId: String?
    private var isAwaitingLeaveAck = false
    private var pendingJoinRoomId: String?
    private var suppressReconnectOnce = false
    private var hadP2POnce = false

    override init() {
        super.init()
        signaling.delegate = self
        pcm.delegate = self
        loadSessions()
    }

    deinit {
        // Avoid heavy sync work on deinit; perform a lightweight teardown.
        signaling.disconnect()
        pcm.close()
    }

    // Public API
    func connect() { signaling.connect() }

    func disconnect() {
        signaling.disconnect()
        pcm.close()
        messages.removeAll()
        roomId = ""
        isP2PConnected = false
        connectionStatus = .disconnected
        clientId = nil
        pendingJoinRoomId = nil
        isAwaitingLeaveAck = false
    }

    func joinRoom(roomId: String) {
    if isEphemeral { messages.removeAll() }
        if connectionStatus != .connected {
            pendingJoinRoomId = roomId
            connect()
            return
        }
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
    }

    // MARK: - Deep Link Handling (inviso://join/<code>)
    /// Entry point for handling a custom URL of the form inviso://join/<6-digit-code>
    /// Accepts the code, creates/updates a session, and attempts to join if room resolved.
    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "inviso" else { return }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Expect path starts with "join" then code component
        let parts = path.split(separator: "/")
        guard parts.count == 2, parts[0].lowercased() == "join" else { return }
        let code = String(parts[1])
        handleJoinCodeFromDeepLink(code: code)
    }

    private func handleJoinCodeFromDeepLink(code: String) {
        // Validate 6-digit pattern
        guard code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else { return }
        // If already have an accepted or pending session with this code, select it
        if let existing = sessions.first(where: { $0.code == code && $0.status != .closed }) {
            activeSessionId = existing.id
            // If already accepted and have roomId, join room automatically
            if let rid = existing.roomId { joinRoom(roomId: rid) }
            return
        }
        // Otherwise attempt accept flow
        Task { [weak self] in
            guard let self = self else { return }
            if let roomId = await self.acceptJoinCode(code) {
                let session = self.addAcceptedSession(name: nil, code: code, roomId: roomId, isCreatedByMe: false)
                self.joinRoom(roomId: roomId)
                self.activeSessionId = session.id
            } else {
                // Create a pending session placeholder so UI can show waiting state
                let pending = ChatSession(name: nil, code: code, createdAt: Date(), expiresAt: Date().addingTimeInterval(5*60), status: .pending, isCreatedByMe: false)
                self.sessions.insert(pending, at: 0)
                self.activeSessionId = pending.id
                self.persistSessions()
            }
        }
    }

    // MARK: - Sessions (frontend only)
    func createSession(name: String?, minutes: Int, code: String) -> ChatSession {
        let expires: Date? = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes) * 60.0) : nil
        let session = ChatSession(name: name, code: code, createdAt: Date(), expiresAt: expires, status: .pending, isCreatedByMe: true)
        sessions.insert(session, at: 0)
        activeSessionId = session.id
    persistSessions()
    Task { await createPendingOnServer(session: session) }
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
    }

    func removeSession(_ session: ChatSession) {
        if let rid = session.roomId { Task { await deleteRoomOnServer(roomId: rid) } }
        sessions.removeAll { $0.id == session.id }
        if activeSessionId == session.id { activeSessionId = nil }
        persistSessions()
    }

    /// Create and persist an accepted session (used for client2 joining by code, or when we already have roomId)
    @discardableResult
    func addAcceptedSession(name: String?, code: String, roomId: String, isCreatedByMe: Bool) -> ChatSession {
        let s = ChatSession(name: name, code: code, roomId: roomId, createdAt: Date(), expiresAt: nil, status: .accepted, isCreatedByMe: isCreatedByMe)
        sessions.insert(s, at: 0)
        activeSessionId = s.id
        persistSessions()
        return s
    }

    // MARK: - Backend REST integration
    private func createPendingOnServer(session: ChatSession) async {
        let joinid = session.code
        let expISO: String
        if let exp = session.expiresAt { expISO = ISO8601DateFormatter().string(from: exp) } else { expISO = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300)) }
        let client1 = DeviceIDManager.shared.id
        var req = URLRequest(url: apiBase.appendingPathComponent("/api/rooms"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["joinid": joinid, "exp": expISO, "client1": client1]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do { _ = try await URLSession.shared.data(for: req) } catch { print("createPending error: \(error)") }
    }

    func acceptJoinCode(_ code: String) async -> String? {
        let client2 = DeviceIDManager.shared.id
        var req = URLRequest(url: apiBase.appendingPathComponent("/api/rooms/accept"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["joinid": code, "client2": client2])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return nil }
            if http.statusCode == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rid = json["roomid"] as? String { return rid }
            if http.statusCode == 404 || http.statusCode == 409 { return nil }
        } catch { print("acceptJoinCode error: \(error)") }
        return nil
    }

    func checkPendingOnServer(joinid: String) async -> String? {
        let client1 = DeviceIDManager.shared.id
        var req = URLRequest(url: apiBase.appendingPathComponent("/api/rooms/check"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["joinid": joinid, "client1": client1])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return nil }
            if http.statusCode == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rid = json["roomid"] as? String { return rid }
            if http.statusCode == 204 { return nil }
            if http.statusCode == 404 { return nil }
        } catch { print("checkPending error: \(error)") }
        return nil
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
        Task {
            // 1) For each pending session, check acceptance
            for i in sessions.indices {
                let s = sessions[i]
                if s.status == .pending {
                    if let rid = await checkPendingOnServer(joinid: s.code) {
                        sessions[i].status = .accepted
                        sessions[i].roomId = rid
                        persistSessions()
                    }
                }
            }
            // 2) For accepted sessions with roomId, verify room still exists
            for i in sessions.indices {
                let s = sessions[i]
                if s.status == .accepted, let rid = s.roomId {
                    let exists = await getRoom(roomId: rid) != nil
                    if !exists {
                        sessions[i].status = .closed
                        sessions[i].roomId = nil
                        persistSessions()
                    }
                }
            }
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
            pcm.createPeerConnection(isInitiator: isInitiator)
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
            if self.pcm.pc == nil { self.pcm.createPeerConnection(isInitiator: false) }
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
            self.pcm.close()
            self.roomId = ""
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
    // When WS connects, also validate backend state (pendings/rooms)
    pollPendingAndValidateRooms()
        if let pending = pendingJoinRoomId { pendingJoinRoomId = nil; joinRoom(roomId: pending) }
    }
    func signalingMessage(_ json: [String : Any]) { handleServerMessage(json) }
    func signalingClosed() { connectionStatus = .disconnected }
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
        }
    }
    func pcmDidReceiveMessage(_ text: String) {
        messages.append(ChatMessage(text: text, timestamp: Date(), isFromSelf: false))
    }
}
