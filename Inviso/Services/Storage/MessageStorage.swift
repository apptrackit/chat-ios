//
//  MessageStorage.swift
//  Inviso
//
//  Privacy-first message storage with automatic expiration
//  Messages are stored per-session in encrypted files with expiry metadata
//

import Foundation

/// Manages local message storage with automatic expiration cleanup
final class MessageStorage {
    static let shared = MessageStorage()
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Storage Directory
    
    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let messagesDir = appSupport.appendingPathComponent("Messages", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: messagesDir.path) {
            try? fileManager.createDirectory(at: messagesDir, withIntermediateDirectories: true)
        }
        
        return messagesDir
    }
    
    private func fileURL(for sessionId: UUID) -> URL {
        return storageDirectory.appendingPathComponent("\(sessionId.uuidString).json")
    }
    
    // MARK: - Public API
    
    /// Save messages for a session
    func saveMessages(_ messages: [ChatMessage], for sessionId: UUID) throws {
        let fileURL = fileURL(for: sessionId)
        
        // Only save non-system messages
        let messagesToSave = messages.filter { !$0.isSystem }
        
        let data = try encoder.encode(messagesToSave)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        
        print("[MessageStorage] 💾 Saved \(messagesToSave.count) messages for session \(sessionId)")
    }
    
    /// Load messages for a session, automatically filtering expired ones
    func loadMessages(for sessionId: UUID) throws -> [ChatMessage] {
        let fileURL = fileURL(for: sessionId)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("[MessageStorage] ℹ️ No messages file found for session \(sessionId)")
            return []
        }
        
        let data = try Data(contentsOf: fileURL)
        var messages = try decoder.decode([ChatMessage].self, from: data)
        
        // Filter out expired messages
        let originalCount = messages.count
        messages.removeAll { $0.isExpired }
        
        if messages.count != originalCount {
            print("[MessageStorage] 🗑️ Filtered \(originalCount - messages.count) expired messages")
            // Save cleaned list back to disk
            try? saveMessages(messages, for: sessionId)
        }
        
        print("[MessageStorage] 📖 Loaded \(messages.count) messages for session \(sessionId)")
        return messages
    }
    
    /// Delete messages for a specific session
    func deleteMessages(for sessionId: UUID) throws {
        let fileURL = fileURL(for: sessionId)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("[MessageStorage] ℹ️ No messages to delete for session \(sessionId)")
            return
        }
        
        try fileManager.removeItem(at: fileURL)
        print("[MessageStorage] 🗑️ Deleted messages for session \(sessionId)")
    }
    
    /// Delete all expired messages across all sessions
    func cleanupExpiredMessages() {
        print("[MessageStorage] 🧹 Starting cleanup of expired messages...")
        
        guard let files = try? fileManager.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil
        ) else {
            print("[MessageStorage] ⚠️ Could not list message files")
            return
        }
        
        var totalCleaned = 0
        
        for fileURL in files where fileURL.pathExtension == "json" {
            // Extract session ID from filename
            let filename = fileURL.deletingPathExtension().lastPathComponent
            guard let sessionId = UUID(uuidString: filename) else { continue }
            
            do {
                // Load and filter messages
                var messages = try decoder.decode([ChatMessage].self, from: Data(contentsOf: fileURL))
                let originalCount = messages.count
                messages.removeAll { $0.isExpired }
                
                if messages.count != originalCount {
                    totalCleaned += (originalCount - messages.count)
                    
                    if messages.isEmpty {
                        // Delete empty file
                        try fileManager.removeItem(at: fileURL)
                        print("[MessageStorage] 🗑️ Deleted empty message file for \(sessionId)")
                    } else {
                        // Save cleaned messages
                        let data = try encoder.encode(messages)
                        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
                    }
                }
            } catch {
                print("[MessageStorage] ⚠️ Error cleaning session \(sessionId): \(error)")
            }
        }
        
        if totalCleaned > 0 {
            print("[MessageStorage] ✅ Cleaned \(totalCleaned) expired messages")
        } else {
            print("[MessageStorage] ✅ No expired messages found")
        }
    }
    
    /// Delete all stored messages (for erase all data operation)
    func eraseAll() {
        print("[MessageStorage] 🗑️ Erasing all stored messages...")
        
        guard let files = try? fileManager.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil
        ) else {
            print("[MessageStorage] ⚠️ Could not list message files for erasure")
            return
        }
        
        var deletedCount = 0
        for fileURL in files where fileURL.pathExtension == "json" {
            try? fileManager.removeItem(at: fileURL)
            deletedCount += 1
        }
        
        print("[MessageStorage] ✅ Erased \(deletedCount) message files")
    }
    
    /// Get total message count for a session (for debugging/stats)
    func getMessageCount(for sessionId: UUID) -> Int {
        do {
            let messages = try loadMessages(for: sessionId)
            return messages.count
        } catch {
            return 0
        }
    }
    
    /// Check if messages exist for a session
    func hasMessages(for sessionId: UUID) -> Bool {
        let fileURL = fileURL(for: sessionId)
        return fileManager.fileExists(atPath: fileURL.path)
    }
}
