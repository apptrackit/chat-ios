import Foundation

protocol SignalingClientDelegate: AnyObject {
    func signalingConnected(clientId: String)
    func signalingMessage(_ json: [String: Any])
    func signalingClosed()
}

final class SignalingClient {
    weak var delegate: SignalingClientDelegate?
    private(set) var status: ConnectionStatus = .disconnected
    private var webSocket: URLSessionWebSocketTask?
    private var url: URL
    private var pingTimer: Timer?
    private var isPinging = false
    private var reconnectWorkItem: DispatchWorkItem?

    init(serverURL: String) {
        self.url = URL(string: serverURL)!
    }

    func connect() {
        guard webSocket == nil else { return }
        status = .connecting
        let urlSession = URLSession(configuration: .default)
        let ws = urlSession.webSocketTask(with: url)
        webSocket = ws
        ws.resume()
        startHeartbeat()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.sendPing() }
        receive()
    }

    func disconnect() {
        stopHeartbeat()
        reconnectWorkItem?.cancel()
        let ws = webSocket
        webSocket = nil
        status = .disconnected
        delegate?.signalingClosed()
        DispatchQueue.global(qos: .utility).async {
            ws?.cancel(with: .goingAway, reason: nil)
        }
    }

    func send(_ dict: [String: Any]) {
        guard let ws = webSocket else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(text)) { error in
            if let error = error { print("WS send error: \(error.localizedDescription)") }
        }
    }

    private func receive() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["type"] as? String {
                        if type == "connected" {
                            self.status = .connected
                            let clientId = json["clientId"] as? String ?? ""
                            self.delegate?.signalingConnected(clientId: clientId)
                        }
                        self.delegate?.signalingMessage(json)
                    }
                case .data(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.delegate?.signalingMessage(json)
                    }
                @unknown default:
                    break
                }
                self.receive()
            case .failure(let error):
                print("WS receive error: \(error.localizedDescription)")
                self.failAndReconnect()
            }
        }
    }

    private func startHeartbeat() {
        stopHeartbeat()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
        if let timer = pingTimer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func stopHeartbeat() {
        pingTimer?.invalidate()
        pingTimer = nil
        isPinging = false
    }

    private func sendPing() {
        guard let ws = webSocket, !isPinging else { return }
        isPinging = true
        var completed = false
        ws.sendPing { [weak self] error in
            guard let self = self else { return }
            completed = true
            self.isPinging = false
            if let error = error {
                print("WS ping error: \(error.localizedDescription)")
                self.failAndReconnect()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else { return }
            if !completed {
                print("WS ping timeout")
                self.isPinging = false
                self.failAndReconnect()
            }
        }
    }

    private func failAndReconnect() {
        stopHeartbeat()
        webSocket?.cancel(with: .abnormalClosure, reason: nil)
        webSocket = nil
        status = .disconnected
        delegate?.signalingClosed()
        reconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
}
