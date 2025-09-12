//
//  ChatManager.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/12/25.
//

import Foundation
import WebRTC
import Combine

enum ConnectionStatus: String, CaseIterable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let isFromSelf: Bool
}

@MainActor
class ChatManager: NSObject, ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var messages: [ChatMessage] = []
    @Published var roomId: String = ""
    @Published var isP2PConnected: Bool = false
    
    private var webSocket: URLSessionWebSocketTask?
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var peerConnectionFactory: RTCPeerConnectionFactory!
    private var clientId: String?
    private var pendingIceCandidates: [RTCIceCandidate] = []
    
    private let signalingServerURL = "wss://chat.ballabotond.com"
    // For local testing, use: "ws://localhost:8080"
    
    override init() {
        super.init()
        setupWebRTC()
    }
    
    deinit {
        Task { @MainActor in
            disconnect()
        }
    }
    
    // MARK: - Public Methods
    
    func connect() {
        guard webSocket == nil else { return }
        
        guard let url = URL(string: signalingServerURL) else {
            print("Invalid signaling server URL: \(signalingServerURL)")
            return
        }
        
        print("Connecting to WebSocket: \(url.absoluteString)")
        connectionStatus = .connecting
        let urlSession = URLSession(configuration: .default)
        webSocket = urlSession.webSocketTask(with: url)
        webSocket?.resume()
        
        // Send a ping to test connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.webSocket?.sendPing { error in
                if let error = error {
                    print("WebSocket ping failed: \(error)")
                } else {
                    print("WebSocket ping successful")
                }
            }
        }
        
        receiveMessages()
    }
    
    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        peerConnection?.close()
        peerConnection = nil
        dataChannel = nil
        
        connectionStatus = .disconnected
        isP2PConnected = false
        roomId = ""
        clientId = nil
        pendingIceCandidates.removeAll()
    }
    
    func joinRoom(roomId: String) {
        self.roomId = roomId
        sendMessage(type: "join_room", payload: ["roomId": roomId])
    }
    
    func sendMessage(_ text: String) {
        guard isP2PConnected, let dataChannel = dataChannel else {
            print("❌ Cannot send message: P2P connection not ready. isP2PConnected: \(isP2PConnected), dataChannel: \(dataChannel != nil)")
            return
        }
        
        guard dataChannel.readyState == .open else {
            print("❌ Cannot send message: Data channel not open. State: \(dataChannel.readyState.rawValue)")
            return
        }
        
        print("📤 Sending message: '\(text)'")
        let message = ChatMessage(text: text, timestamp: Date(), isFromSelf: true)
        messages.append(message)
        
        // Send via WebRTC data channel
        guard let data = text.data(using: .utf8) else {
            print("❌ Failed to encode message as UTF-8")
            return
        }
        
        let buffer = RTCDataBuffer(data: data, isBinary: false)
        let success = dataChannel.sendData(buffer)
        print("📤 Message send result: \(success)")
    }
    
    // MARK: - Private Methods
    
    private func setupWebRTC() {
        // Initialize WebRTC
        RTCInitializeSSL()
        
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
    }
    
    private func createPeerConnection(isInitiator: Bool = false) {
        print("📡 Creating peer connection... (isInitiator: \(isInitiator))")
        
        let configuration = RTCConfiguration()
        configuration.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun2.l.google.com:19302"])
        ]
        configuration.iceCandidatePoolSize = 10
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )
        
        peerConnection = peerConnectionFactory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        )
        
        if peerConnection != nil {
            print("✅ Peer connection created successfully")
            // Only the initiator creates the data channel
            // The receiver will get it via didOpen delegate method
            if isInitiator {
                createDataChannel()
            } else {
                print("⏳ Waiting for data channel from initiator...")
            }
        } else {
            print("❌ Failed to create peer connection")
        }
    }
    
    private func createDataChannel() {
        print("📡 Creating data channel...")
        
        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = true
        dataChannelConfig.maxRetransmits = -1
        dataChannelConfig.maxPacketLifeTime = -1
        
        dataChannel = peerConnection?.dataChannel(
            forLabel: "chat",
            configuration: dataChannelConfig
        )
        dataChannel?.delegate = self
        
        if dataChannel != nil {
            print("✅ Data channel created successfully (for sending)")
        } else {
            print("❌ Failed to create data channel")
        }
    }
    
    private func createOffer() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )
        
        peerConnection?.offer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp, error == nil else {
                print("Failed to create offer: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            self.peerConnection?.setLocalDescription(sdp) { error in
                if let error = error {
                    print("Failed to set local description: \(error.localizedDescription)")
                    return
                }
                
                // Send offer to signaling server
                Task { @MainActor in
                    self.sendSignalingMessage(type: "webrtc_offer", payload: [
                        "sdp": sdp.sdp
                    ])
                }
            }
        }
    }
    
    private func createAnswer(for offer: RTCSessionDescription) {
        peerConnection?.setRemoteDescription(offer) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                print("Failed to set remote description: \(error.localizedDescription)")
                return
            }
            
            print("✅ Remote description set successfully")
            
            // Add any pending ICE candidates now that we have remote description
            Task { @MainActor in
                print("🗂️ Adding \(self.pendingIceCandidates.count) pending ICE candidates")
                for candidate in self.pendingIceCandidates {
                    self.addIceCandidate(candidate)
                }
                self.pendingIceCandidates.removeAll()
            }
            
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: [
                    "OfferToReceiveAudio": "false",
                    "OfferToReceiveVideo": "false"
                ],
                optionalConstraints: nil
            )
            
            self.peerConnection?.answer(for: constraints) { sdp, error in
                guard let sdp = sdp, error == nil else {
                    print("Failed to create answer: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                self.peerConnection?.setLocalDescription(sdp) { error in
                    if let error = error {
                        print("Failed to set local description: \(error.localizedDescription)")
                        return
                    }
                    
                    print("✅ Local description (answer) set successfully")
                    
                    // Send answer to signaling server
                    Task { @MainActor in
                        self.sendSignalingMessage(type: "webrtc_answer", payload: [
                            "sdp": sdp.sdp
                        ])
                    }
                }
            }
        }
    }
    
    private func addIceCandidate(_ candidate: RTCIceCandidate) {
        peerConnection?.add(candidate) { error in
            if let error = error {
                print("Failed to add ICE candidate: \(error.localizedDescription)")
            } else {
                print("Successfully added ICE candidate")
            }
        }
    }
    
    private func sendSignalingMessage(type: String, payload: [String: Any]) {
        sendMessage(type: type, payload: payload)
    }
    
    private func sendMessage(type: String, payload: [String: Any] = [:]) {
        var messageDict: [String: Any] = ["type": type]
        if !payload.isEmpty {
            messageDict.merge(payload) { _, new in new }
        }
        
        guard let data = try? JSONSerialization.data(withJSONObject: messageDict),
              let message = String(data: data, encoding: .utf8) else {
            print("Failed to serialize message")
            return
        }
        
        let webSocketMessage = URLSessionWebSocketTask.Message.string(message)
        webSocket?.send(webSocketMessage) { error in
            if let error = error {
                print("Failed to send WebSocket message: \(error.localizedDescription)")
            }
        }
    }
    
    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleWebSocketMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleWebSocketMessage(text)
                    }
                @unknown default:
                    break
                }
                
                // Continue receiving messages
                self.receiveMessages()
                
            case .failure(let error):
                print("WebSocket receive error: \(error.localizedDescription)")
                print("Error code: \((error as NSError).code)")
                print("Error domain: \((error as NSError).domain)")
                Task { @MainActor in
                    self.connectionStatus = .disconnected
                    // Try to reconnect after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if self.connectionStatus == .disconnected {
                            print("Attempting to reconnect...")
                            self.connect()
                        }
                    }
                }
            }
        }
    }
    
    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            print("Failed to parse WebSocket message: \(text)")
            return
        }
        
        Task { @MainActor in
            switch type {
            case "connected":
                self.connectionStatus = .connected
                self.clientId = json["clientId"] as? String
                print("Connected to signaling server with ID: \(self.clientId ?? "unknown")")
                
            case "room_joined":
                if let roomId = json["roomId"] as? String {
                    self.roomId = roomId
                    print("Joined room: \(roomId)")
                }
                
            case "room_ready":
                print("🎯 Room is ready! Both users connected")
                
                // Use client ID to determine who creates the offer (avoid collision)
                let shouldCreateOffer = json["isInitiator"] as? Bool ?? false
                print("Should create offer: \(shouldCreateOffer), Client ID: \(self.clientId ?? "unknown")")
                
                self.createPeerConnection(isInitiator: shouldCreateOffer)
                
                if shouldCreateOffer {
                    // Wait a moment for peer connection to be fully set up
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        print("🚀 Creating offer as initiator")
                        self.createOffer()
                    }
                } else {
                    print("⏳ Waiting for offer from initiator...")
                }
                
            case "webrtc_offer":
                self.handleOffer(json)
                
            case "webrtc_answer":
                self.handleAnswer(json)
                
            case "ice_candidate":
                self.handleIceCandidate(json)
                
            case "peer_disconnected":
                self.isP2PConnected = false
                self.peerConnection?.close()
                self.peerConnection = nil
                self.dataChannel = nil
                
            case "error":
                if let error = json["error"] as? String {
                    print("Server error: \(error)")
                }
                
            default:
                print("Unknown message type: \(type)")
            }
        }
    }
    
    private func handleOffer(_ json: [String: Any]) {
        print("📥 Received WebRTC offer")
        guard let sdp = json["sdp"] as? String else {
            print("Invalid offer format - missing SDP")
            return
        }
        
        print("Offer SDP length: \(sdp.count)")
        let sessionDescription = RTCSessionDescription(
            type: .offer,
            sdp: sdp
        )
        
        // Create peer connection if we don't have one
        if peerConnection == nil {
            createPeerConnection(isInitiator: false) // Receiver doesn't create data channel
        }
        
        // Check if we have a collision (both sides created offers)
        if peerConnection?.signalingState == .haveLocalOffer {
            print("⚠️ Offer collision detected! Resolving...")
            // Standard WebRTC collision resolution: compare client IDs
            let remoteClientId = json["from"] as? String ?? ""
            let localClientId = self.clientId ?? ""
            
            if localClientId.compare(remoteClientId) == .orderedDescending {
                // We win the collision, ignore the remote offer
                print("🏆 We win collision, ignoring remote offer")
                return
            } else {
                // They win, restart as answerer
                print("👥 They win collision, restarting as answerer")
                peerConnection?.close()
                createPeerConnection(isInitiator: false)
            }
        }
        
        createAnswer(for: sessionDescription)
    }
    
    private func handleAnswer(_ json: [String: Any]) {
        print("Received WebRTC answer")
        guard let sdp = json["sdp"] as? String else {
            print("Invalid answer format - missing SDP")
            return
        }
        
        print("Answer SDP length: \(sdp.count)")
        let sessionDescription = RTCSessionDescription(
            type: .answer,
            sdp: sdp
        )
        
        peerConnection?.setRemoteDescription(sessionDescription) { [weak self] error in
            if let error = error {
                print("Failed to set remote description (answer): \(error.localizedDescription)")
            } else {
                print("✅ Remote description (answer) set successfully")
                
                // Add any pending ICE candidates now that we have remote description
                Task { @MainActor in
                    guard let self = self else { return }
                    print("🗂️ Adding \(self.pendingIceCandidates.count) pending ICE candidates")
                    for candidate in self.pendingIceCandidates {
                        self.addIceCandidate(candidate)
                    }
                    self.pendingIceCandidates.removeAll()
                }
            }
        }
    }
    
    private func handleIceCandidate(_ json: [String: Any]) {
        print("📥 Received ICE candidate")
        guard let candidateDict = json["candidate"] as? [String: Any],
              let candidate = candidateDict["candidate"] as? String,
              let sdpMLineIndex = candidateDict["sdpMLineIndex"] as? Int32,
              let sdpMid = candidateDict["sdpMid"] as? String else {
            print("Invalid ICE candidate format: \(json)")
            return
        }
        
        print("ICE candidate: \(candidate)")
        let iceCandidate = RTCIceCandidate(
            sdp: candidate,
            sdpMLineIndex: sdpMLineIndex,
            sdpMid: sdpMid
        )
        
        // If we don't have a remote description yet, store the candidate
        if peerConnection?.remoteDescription == nil {
            print("🗂️ Storing ICE candidate for later (no remote description yet)")
            pendingIceCandidates.append(iceCandidate)
        } else {
            addIceCandidate(iceCandidate)
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

extension ChatManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChange: RTCSignalingState) {
        print("Signaling state changed: \(stateChange.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("Media stream added")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("Media stream removed")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("Peer connection should negotiate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("🔵 ICE connection state changed: \(newState.rawValue)")
        
        Task { @MainActor in
            switch newState {
            case .new:
                print("ICE: New connection")
            case .checking:
                print("ICE: Checking connectivity")
            case .connected:
                print("🟢 ICE: Connected! P2P connection established")
                self.isP2PConnected = true
            case .completed:
                print("🟢 ICE: Completed! P2P connection fully established")
                self.isP2PConnected = true
            case .failed:
                print("🔴 ICE: Connection failed")
                self.isP2PConnected = false
            case .disconnected:
                print("🟡 ICE: Disconnected")
                self.isP2PConnected = false
            case .closed:
                print("🔴 ICE: Connection closed")
                self.isP2PConnected = false
            case .count:
                break
            @unknown default:
                print("ICE: Unknown state")
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("ICE gathering state changed: \(newState.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("📤 Generated ICE candidate: \(candidate.sdp)")
        
        Task { @MainActor in
            self.sendSignalingMessage(type: "ice_candidate", payload: [
                "candidate": [
                    "candidate": candidate.sdp,
                    "sdpMLineIndex": candidate.sdpMLineIndex,
                    "sdpMid": candidate.sdpMid ?? ""
                ]
            ])
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("Removed ICE candidates")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("📡 Data channel opened by peer: \(dataChannel.label)")
        
        // This is called when the REMOTE peer opens a data channel
        // We need to set this as our data channel for receiving messages
        self.dataChannel = dataChannel
        dataChannel.delegate = self
        
        Task { @MainActor in
            self.isP2PConnected = true
            print("✅ P2P connection fully established with data channel: \(dataChannel.label)")
        }
    }
}

// MARK: - RTCDataChannelDelegate

extension ChatManager: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("📡 Data channel state changed: \(dataChannel.readyState.rawValue)")
        
        Task { @MainActor in
            switch dataChannel.readyState {
            case .connecting:
                print("📡 Data channel: Connecting...")
            case .open:
                print("🟢 Data channel: Open! Ready to send messages")
                self.isP2PConnected = true
            case .closing:
                print("📡 Data channel: Closing...")
            case .closed:
                print("🔴 Data channel: Closed")
                self.isP2PConnected = false
            @unknown default:
                print("📡 Data channel: Unknown state")
            }
        }
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let data = buffer.data
        print("📥 Received raw data: \(data.count) bytes")
        
        guard let message = String(data: data, encoding: .utf8) else {
            print("❌ Failed to decode received message from \(data.count) bytes")
            print("Raw data: \(data)")
            return
        }
        
        print("📥 Received P2P message: '\(message)'")
        
        Task { @MainActor in
            let chatMessage = ChatMessage(text: message, timestamp: Date(), isFromSelf: false)
            self.messages.append(chatMessage)
            print("✅ Message added to chat: '\(message)'")
        }
    }
}
