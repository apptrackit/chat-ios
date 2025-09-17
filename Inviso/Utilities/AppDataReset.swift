import Foundation
import SwiftUI

enum AppDataReset {
    /// Calls backend purge and clears all local app storage and caches.
    static func eraseAll(deviceId: String) async {
        await purgeServerData(deviceId: deviceId)
        clearLocalStores()
        // Device ID will be reset outside by caller to update UI state.
    }

    /// Best-effort server purge using the known API.
    static func purgeServerData(deviceId: String) async {
        guard let url = URL(string: "https://chat.ballabotond.com/api/user/purge") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["deviceId": deviceId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode != 200 {
                    print("Purge server responded with status: \(http.statusCode)")
                }
            }
        } catch {
            // Non-fatal: still continue with local wipe
            print("Purge server error: \(error.localizedDescription)")
        }
    }

    /// Clears UserDefaults, caches, tmp, and URLCache.
    static func clearLocalStores() {
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
