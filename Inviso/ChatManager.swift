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

    // Components
    private let signaling = SignalingClient(serverURL: "wss://chat.ballabotond.com")
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
        if isEphemeral { messages.removeAll() }
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
        }
    }
    func pcmDidReceiveMessage(_ text: String) {
        messages.append(ChatMessage(text: text, timestamp: Date(), isFromSelf: false))
    }
}
