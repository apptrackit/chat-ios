import Foundation
import SwiftUI

enum AppDataReset {
    /// Calls backend purge and clears all local app storage and caches.
    static func eraseAll() async {
        // Get all ephemeral IDs before wiping
        let ephemeralIds = DeviceIDManager.shared.getEphemeralIDs().map { $0.id }
        
        print("[AppDataReset] Found \(ephemeralIds.count) ephemeral IDs to purge")
        
        if !ephemeralIds.isEmpty {
            print("[AppDataReset] Purging ephemeral IDs from server: \(ephemeralIds)")
            await purgeServerData(ephemeralIds: ephemeralIds)
        } else {
            print("[AppDataReset] No ephemeral IDs to purge")
        }
        
        clearLocalStores()
        print("[AppDataReset] Local stores cleared")
    }

    /// Best-effort server purge using list of ephemeral device IDs.
    /// Server should delete all rooms/data associated with these IDs.
    static func purgeServerData(ephemeralIds: [String]) async {
        guard let url = URL(string: "https://\(ServerConfig.shared.host)/api/user/purge") else {
            print("[AppDataReset] Failed to create purge URL")
            return
        }
        
        print("[AppDataReset] Sending purge request to: \(url.absoluteString)")
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["deviceIds": ephemeralIds]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 {
                    print("[AppDataReset] Server purge successful")
                    if let responseStr = String(data: data, encoding: .utf8) {
                        print("[AppDataReset] Response: \(responseStr)")
                    }
                } else {
                    print("[AppDataReset] Purge server responded with status: \(http.statusCode)")
                    if let responseStr = String(data: data, encoding: .utf8) {
                        print("[AppDataReset] Error response: \(responseStr)")
                    }
                }
            }
        } catch {
            // Non-fatal: still continue with local wipe
            print("[AppDataReset] Purge server error: \(error.localizedDescription)")
        }
    }

    /// Clears UserDefaults, caches, tmp, and URLCache.
    static func clearLocalStores() {
        // Clear ephemeral IDs from keychain
        DeviceIDManager.shared.clearAllEphemeralIDs()
        
        // UserDefaults
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
        }

        // URLCache
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.diskCapacity = 0
        URLCache.shared.memoryCapacity = 0

        // Caches and tmp directories
        let fm = FileManager.default
        let dirs: [URL?] = [
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: NSTemporaryDirectory()),
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ]
        for dir in dirs.compactMap({ $0 }) {
            if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for url in contents {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }
}
