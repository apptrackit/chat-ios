import Foundation
import WebRTC

protocol PeerConnectionManagerDelegate: AnyObject {
    func pcmDidGenerateIce(_ candidate: RTCIceCandidate)
    func pcmIceStateChanged(connected: Bool)
    func pcmDidReceiveMessage(_ text: String)
}

final class PeerConnectionManager: NSObject {
    weak var delegate: PeerConnectionManagerDelegate?
    private var factory: RTCPeerConnectionFactory!
    private(set) var pc: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var pending = [RTCIceCandidate]()

    private static var didInitSSL: Bool = false

    override init() {
        super.init()
        if !Self.didInitSSL {
            RTCInitializeSSL()
            Self.didInitSSL = true
        }
        let enc = RTCDefaultVideoEncoderFactory()
        let dec = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: enc, decoderFactory: dec)
    }

    func createPeerConnection(isInitiator: Bool) {
    if pc != nil { close() }
        let configuration = RTCConfiguration()
        configuration.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["turn:chat.ballabotond.com:3478"], username: "testuser", credential: "testpass"),
            RTCIceServer(urlStrings: ["turn:chat.ballabotond.com:3478?transport=tcp"], username: "testuser", credential: "testpass"),
            RTCIceServer(urlStrings: ["turns:chat.ballabotond.com:5349"], username: "testuser", credential: "testpass"),
            RTCIceServer(urlStrings: ["turn:openrelay.metered.ca:80"], username: "openrelayproject", credential: "openrelayproject"),
            RTCIceServer(urlStrings: ["turn:openrelay.metered.ca:443"], username: "openrelayproject", credential: "openrelayproject"),
            RTCIceServer(urlStrings: ["turn:openrelay.metered.ca:443?transport=tcp"], username: "openrelayproject", credential: "openrelayproject")
        ]
        configuration.iceCandidatePoolSize = 2
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        configuration.iceTransportPolicy = .all
        configuration.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        pc = factory.peerConnection(with: configuration, constraints: constraints, delegate: self)
        if isInitiator {
            let conf = RTCDataChannelConfiguration()
            conf.isOrdered = true
            conf.maxRetransmits = -1
            conf.maxPacketLifeTime = -1
            dataChannel = pc?.dataChannel(forLabel: "chat", configuration: conf)
            dataChannel?.delegate = self
        }
    }

    func close() {
        // Teardown off the main thread to avoid blocking UI during WebRTC shutdown.
        let dc = dataChannel
        let peer = pc
        // Nil out references first to stop callbacks while tearing down.
        dataChannel = nil
        pc = nil
        pending.removeAll()
        DispatchQueue.global(qos: .userInitiated).async {
            dc?.close()
            peer?.close()
        }
    }

    func createOffer(completion: @escaping (RTCSessionDescription?) -> Void) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: [
            "OfferToReceiveAudio": "false",
            "OfferToReceiveVideo": "false"
        ], optionalConstraints: nil)
        pc?.offer(for: constraints) { [weak self] sdp, _ in
            guard let self = self, let sdp = sdp else { completion(nil); return }
            self.pc?.setLocalDescription(sdp, completionHandler: { _ in completion(sdp) })
        }
    }

    func setRemoteOfferAndCreateAnswer(_ offer: RTCSessionDescription, completion: @escaping (RTCSessionDescription?) -> Void) {
        pc?.setRemoteDescription(offer) { [weak self] err in
            guard let self = self, err == nil else { completion(nil); return }
            self.flushPending()
            let constraints = RTCMediaConstraints(mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ], optionalConstraints: nil)
            self.pc?.answer(for: constraints) { sdp, _ in
                guard let sdp = sdp else { completion(nil); return }
                self.pc?.setLocalDescription(sdp, completionHandler: { _ in completion(sdp) })
            }
        }
    }

    func setRemoteAnswer(_ answer: RTCSessionDescription, completion: @escaping (Bool) -> Void) {
        pc?.setRemoteDescription(answer) { [weak self] err in
            guard let self = self else { completion(false); return }
            if err == nil { self.flushPending(); completion(true) } else { completion(false) }
        }
    }

    func addRemoteCandidate(_ c: RTCIceCandidate) {
        if pc?.remoteDescription == nil { pending.append(c) } else { pc?.add(c) }
    }

    func send(_ text: String) -> Bool {
        guard let dc = dataChannel, dc.readyState == .open else { return false }
        let buf = RTCDataBuffer(data: Data(text.utf8), isBinary: false)
        return dc.sendData(buf)
    }

    private func flushPending() { guard let pc = pc else { return }; pending.forEach { pc.add($0) }; pending.removeAll() }
}

extension PeerConnectionManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChange: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let connected = (newState == .connected || newState == .completed)
        delegate?.pcmIceStateChanged(connected: connected)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        delegate?.pcmDidGenerateIce(candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        self.dataChannel = dataChannel
        dataChannel.delegate = self
        delegate?.pcmIceStateChanged(connected: true)
    }
}

extension PeerConnectionManager: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if let text = String(data: buffer.data, encoding: .utf8) { delegate?.pcmDidReceiveMessage(text) }
    }
}
