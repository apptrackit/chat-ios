//
//  ChatManager.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/12/25.
//

import Foundation
import WebRTC

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
    
    private let signalingServerURL = "wss://chat.ballabotond.com"
    // For local testing, use: "ws://localhost:8080"
    
    override init() {
        super.init()
        setupWebRTC()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Public Methods
    
    func connect() {
        guard webSocket == nil else { return }
        
        guard let url = URL(string: signalingServerURL) else {
            print("Invalid signaling server URL")
            return
        }
        
        connectionStatus = .connecting
        webSocket = URLSession.shared.webSocketTask(with: url)
        webSocket?.resume()
        
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
    }
    
    func joinRoom(roomId: String) {
        self.roomId = roomId
        sendMessage(type: "join_room", payload: ["roomId": roomId])
    }
    
    func sendMessage(_ text: String) {
        guard isP2PConnected, let dataChannel = dataChannel else {
            print("Cannot send message: P2P connection not ready")
            return
        }
        
        let message = ChatMessage(text: text, timestamp: Date(), isFromSelf: true)
        messages.append(message)
        
        // Send via WebRTC data channel
        let buffer = RTCDataBuffer(data: text.data(using: .utf8)!, isBinary: false)
        dataChannel.sendData(buffer)
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
    
    private func createPeerConnection() {
        let configuration = RTCConfiguration()
        configuration.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])
        ]
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )
        
        peerConnection = peerConnectionFactory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        )
        
        createDataChannel()
    }
    
    private func createDataChannel() {
        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = true
        
        dataChannel = peerConnection?.dataChannel(
            forLabel: "chat",
            configuration: dataChannelConfig
        )
        dataChannel?.delegate = self
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
                Task { @MainActor in
                    self.connectionStatus = .disconnected
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
                
            case "joined_room":
                if let roomId = json["roomId"] as? String {
                    self.roomId = roomId
                    print("Joined room: \(roomId)")
                }
                
            case "room_ready":
                print("Room is ready, creating peer connection")
                self.createPeerConnection()
                // Check if we're the initiator to create offer
                if let isInitiator = json["isInitiator"] as? Bool, isInitiator {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.createOffer()
                    }
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
        guard let sdp = json["sdp"] as? String,
              let typeString = json["type"] as? String else {
            print("Invalid offer format")
            return
        }
        
        let sessionDescription = RTCSessionDescription(
            type: RTCSdpType(rawValue: typeString) ?? .offer,
            sdp: sdp
        )
        
        createPeerConnection()
        createAnswer(for: sessionDescription)
    }
    
    private func handleAnswer(_ json: [String: Any]) {
        guard let sdp = json["sdp"] as? String,
              let typeString = json["type"] as? String else {
            print("Invalid answer format")
            return
        }
        
        let sessionDescription = RTCSessionDescription(
            type: RTCSdpType(rawValue: typeString) ?? .answer,
            sdp: sdp
        )
        
        peerConnection?.setRemoteDescription(sessionDescription) { error in
            if let error = error {
                print("Failed to set remote description: \(error.localizedDescription)")
            } else {
                print("Successfully set remote description")
            }
        }
    }
    
    private func handleIceCandidate(_ json: [String: Any]) {
        guard let candidateDict = json["candidate"] as? [String: Any],
              let candidate = candidateDict["candidate"] as? String,
              let sdpMLineIndex = candidateDict["sdpMLineIndex"] as? Int32,
              let sdpMid = candidateDict["sdpMid"] as? String else {
            print("Invalid ICE candidate format")
            return
        }
        
        let iceCandidate = RTCIceCandidate(
            sdp: candidate,
            sdpMLineIndex: sdpMLineIndex,
            sdpMid: sdpMid
        )
        
        addIceCandidate(iceCandidate)
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
        print("ICE connection state changed: \(newState.rawValue)")
        
        Task { @MainActor in
            switch newState {
            case .connected, .completed:
                self.isP2PConnected = true
            case .disconnected, .failed, .closed:
                self.isP2PConnected = false
            default:
                break
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("ICE gathering state changed: \(newState.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("Generated ICE candidate")
        
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
        print("Data channel opened: \(dataChannel.label)")
        dataChannel.delegate = self
        
        Task { @MainActor in
            self.isP2PConnected = true
        }
    }
}

// MARK: - RTCDataChannelDelegate

extension ChatManager: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("Data channel state changed: \(dataChannel.readyState.rawValue)")
        
        Task { @MainActor in
            switch dataChannel.readyState {
            case .open:
                self.isP2PConnected = true
            case .closed:
                self.isP2PConnected = false
            default:
                break
            }
        }
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let data = buffer.data,
              let message = String(data: data, encoding: .utf8) else {
            print("Failed to decode received message")
            return
        }
        
        print("Received P2P message: \(message)")
        
        Task { @MainActor in
            let chatMessage = ChatMessage(text: message, timestamp: Date(), isFromSelf: false)
            self.messages.append(chatMessage)
        }
    }
}
