import Foundation
import Combine

/// Central configuration for the signaling/API server host.
/// Persists to UserDefaults so the app can reconnect with the chosen host on next launch.
final class ServerConfig: ObservableObject {
    static let shared = ServerConfig()

    private let storeKey = "server.host.v1"
    private let defaultHost = "chat.ballabotond.com"

    @Published private(set) var host: String

    private init() {
        if let stored = UserDefaults.standard.string(forKey: storeKey), stored.isEmpty == false {
            host = stored
        } else {
            host = defaultHost
        }
    }

    func updateHost(_ newHostRaw: String) {
        let sanitized = ServerConfig.sanitize(newHostRaw)
        guard sanitized.isEmpty == false, sanitized != host else { return }
        host = sanitized
        UserDefaults.standard.set(sanitized, forKey: storeKey)
    }

    func resetToDefault() { updateHost(defaultHost) }

    static func sanitize(_ raw: String) -> String {
        var h = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if h.hasPrefix("https://") { h.removeFirst("https://".count) }
        if h.hasPrefix("http://") { h.removeFirst("http://".count) }
        if h.hasPrefix("wss://") { h.removeFirst("wss://".count) }
        if h.hasPrefix("ws://") { h.removeFirst("ws://".count) }
        while h.hasSuffix("/") { h.removeLast() }
        return h
    }
}