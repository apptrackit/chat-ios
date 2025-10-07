//
//  DeviceIDManager.swift
//  Inviso
//
//  Manages ephemeral device IDs for privacy.
//  Each session gets a unique identifier that cannot be correlated.
//  No persistent device ID is stored.
//

import Foundation

final class DeviceIDManager {
    static let shared = DeviceIDManager()

    private let keychain: KeychainService
    private let ephemeralIDsAccount = "ephemeral-ids"

    private init() {
        // Use bundle identifier for keychain service scoping, with a suffix
        let baseService = Bundle.main.bundleIdentifier ?? "inviso"
        self.keychain = KeychainService(service: baseService + ".deviceid")
    }
    
    // MARK: - Ephemeral ID Management
    
    /// Get all active ephemeral IDs with metadata
    func getEphemeralIDs() -> [EphemeralIDRecord] {
        guard let data = keychain.data(for: ephemeralIDsAccount),
              let records = try? JSONDecoder().decode([EphemeralIDRecord].self, from: data) else {
            return []
        }
        return records
    }
    
    /// Register a new ephemeral ID for a session
    func registerEphemeralID(_ id: String, sessionName: String?, code: String) {
        var records = getEphemeralIDs()
        let record = EphemeralIDRecord(
            id: id,
            sessionName: sessionName,
            code: code,
            createdAt: Date()
        )
        records.append(record)
        saveEphemeralIDs(records)
    }
    
    /// Remove a specific ephemeral ID
    func removeEphemeralID(_ id: String) {
        var records = getEphemeralIDs()
        records.removeAll { $0.id == id }
        saveEphemeralIDs(records)
    }
    
    /// Update the session name for an ephemeral ID
    func updateSessionName(ephemeralId: String, newName: String?) {
        var records = getEphemeralIDs()
        if let idx = records.firstIndex(where: { $0.id == ephemeralId }) {
            var updatedRecord = records[idx]
            updatedRecord.sessionName = newName
            records[idx] = updatedRecord
            saveEphemeralIDs(records)
        }
    }
    
    /// Clear all ephemeral IDs
    func clearAllEphemeralIDs() {
        try? keychain.delete(account: ephemeralIDsAccount)
    }
    
    /// Clean up ephemeral IDs for closed sessions
    func pruneEphemeralIDs(activeSessionIDs: Set<String>) {
        var records = getEphemeralIDs()
        records.removeAll { !activeSessionIDs.contains($0.id) }
        saveEphemeralIDs(records)
    }
    
    private func saveEphemeralIDs(_ records: [EphemeralIDRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? keychain.setData(data, for: ephemeralIDsAccount)
    }
    
    // MARK: - Server Purge
    
    /// Purge a single ephemeral ID from the server
    static func purgeFromServer(ephemeralId: String) async {
        await purgeFromServer(ephemeralIds: [ephemeralId])
    }
    
    /// Purge multiple ephemeral IDs from the server
    static func purgeFromServer(ephemeralIds: [String]) async {
        guard !ephemeralIds.isEmpty else { return }
        guard let url = URL(string: "https://\(ServerConfig.shared.host)/api/user/purge") else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["deviceIds": ephemeralIds]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode != 200 {
                    print("[DeviceIDManager] Server purge failed with status: \(http.statusCode)")
                }
            }
        } catch {
            print("[DeviceIDManager] Server purge error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Ephemeral ID Record

struct EphemeralIDRecord: Codable, Identifiable, Equatable {
    let id: String // The ephemeral device ID
    var sessionName: String? // Mutable to allow updates
    let code: String // Join code for reference
    let createdAt: Date
    
    var displayName: String {
        if let name = sessionName, !name.isEmpty {
            return name
        }
        return "Session \(code)"
    }
    
    var shortID: String {
        String(id.prefix(8))
    }
}
