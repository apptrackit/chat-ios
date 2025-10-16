//
//  NotificationService.swift
//  InvisoNotificationService
//
//  Created by Bence Szilagyi on 10/12/25.
//

import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }
        
        // Log notification received for debugging
        NSLog("🔔 [NotificationService] Received notification")
        NSLog("🔔 [NotificationService] UserInfo: \(request.content.userInfo)")
        
        // Extract roomId from notification payload
        guard let roomId = request.content.userInfo["roomId"] as? String else {
            NSLog("🔔 [NotificationService] No roomId in payload, showing original notification")
            contentHandler(bestAttemptContent)
            return
        }
        
        NSLog("🔔 [NotificationService] Looking up room name for roomId: \(roomId)")
        
        // IMPORTANT: Track this notification in App Group storage
        trackNotification(roomId: roomId, receivedAt: Date())
        
        // Look up room name from shared UserDefaults
        if let roomName = getRoomName(forRoomId: roomId) {
            NSLog("🔔 [NotificationService] Found room name: '\(roomName)'")
            // Modify notification text to include room name
            bestAttemptContent.body = "Someone is waiting in '\(roomName)'"
        } else {
            NSLog("🔔 [NotificationService] Room name not found, using default text")
            // Keep default message if room name not found
        }
        
        // Deliver the modified notification
        contentHandler(bestAttemptContent)
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called if extension takes too long (>30 seconds)
        // Deliver whatever we have so far
        NSLog("🔔 [NotificationService] Extension time will expire, delivering best attempt content")
        if let contentHandler = contentHandler,
           let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
    
    // MARK: - Helper Functions
    
    /// Track notification in App Group storage so main app can sync it later
    private func trackNotification(roomId: String, receivedAt: Date) {
        let appGroupId = "group.com.31b4.inviso"
        let pendingNotificationsKey = "pending_notifications"
        
        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            NSLog("🔔 [NotificationService] ❌ Failed to access App Group UserDefaults for tracking")
            return
        }
        
        // Load existing pending notifications
        var pendingNotifications = sharedDefaults.array(forKey: pendingNotificationsKey) as? [[String: Any]] ?? []
        
        // Add this notification
        let notification: [String: Any] = [
            "id": UUID().uuidString,
            "roomId": roomId,
            "receivedAt": receivedAt.timeIntervalSince1970
        ]
        pendingNotifications.append(notification)
        
        // Save back
        sharedDefaults.set(pendingNotifications, forKey: pendingNotificationsKey)
        sharedDefaults.synchronize()
        
        NSLog("🔔 [NotificationService] ✅ Tracked notification for roomId: \(roomId)")
        NSLog("🔔 [NotificationService] Total pending notifications: \(pendingNotifications.count)")
    }
    
    /// Look up room name from shared UserDefaults (App Group)
    private func getRoomName(forRoomId roomId: String) -> String? {
        let appGroupId = "group.com.31b4.inviso"
        let storeKey = "chat.sessions.v1"
        
        // Access shared UserDefaults
        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            NSLog("🔔 [NotificationService] ❌ Failed to access App Group UserDefaults")
            return nil
        }
        
        // Load sessions from shared storage
        guard let sessionsData = sharedDefaults.data(forKey: storeKey) else {
            NSLog("🔔 [NotificationService] ❌ No sessions data found in App Group")
            return nil
        }
        
        // Decode sessions
        guard let sessions = try? JSONDecoder().decode([ChatSession].self, from: sessionsData) else {
            NSLog("🔔 [NotificationService] ❌ Failed to decode sessions")
            return nil
        }
        
        NSLog("🔔 [NotificationService] Loaded \(sessions.count) sessions from App Group")
        
        // Find matching session
        let session = sessions.first { $0.roomId == roomId }
        
        if let session = session {
            NSLog("🔔 [NotificationService] ✅ Found session: '\(session.name ?? "Unnamed")'")
            return session.name
        } else {
            NSLog("🔔 [NotificationService] ❌ No session found with roomId: \(roomId)")
            return nil
        }
    }
}

// MARK: - ChatSession Model

/// Minimal ChatSession struct for decoding from UserDefaults
/// Must match the structure in the main app's ChatModels.swift
struct ChatSession: Codable {
    let id: UUID
    var name: String?
    var code: String
    var roomId: String?
    var createdAt: Date
    var expiresAt: Date?
    var lastActivityDate: Date
    var firstConnectedAt: Date?
    var closedAt: Date?
    var status: SessionStatus
    var isCreatedByMe: Bool
    var ephemeralDeviceId: String
    var encryptionEnabled: Bool
    var keyExchangeCompletedAt: Date?
    var wasOriginalInitiator: Bool?
    var isPinned: Bool
    var pinnedOrder: Int?
    var notifications: [SessionNotification]
    
    // Custom Codable for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, name, code, roomId, createdAt, expiresAt, lastActivityDate
        case firstConnectedAt, closedAt, status, isCreatedByMe, ephemeralDeviceId
        case encryptionEnabled, keyExchangeCompletedAt, wasOriginalInitiator
        case isPinned, pinnedOrder, notifications
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        code = try container.decode(String.self, forKey: .code)
        roomId = try container.decodeIfPresent(String.self, forKey: .roomId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        lastActivityDate = try container.decodeIfPresent(Date.self, forKey: .lastActivityDate) ?? container.decode(Date.self, forKey: .createdAt)
        firstConnectedAt = try container.decodeIfPresent(Date.self, forKey: .firstConnectedAt)
        closedAt = try container.decodeIfPresent(Date.self, forKey: .closedAt)
        status = try container.decode(SessionStatus.self, forKey: .status)
        isCreatedByMe = try container.decode(Bool.self, forKey: .isCreatedByMe)
        ephemeralDeviceId = try container.decode(String.self, forKey: .ephemeralDeviceId)
        encryptionEnabled = try container.decodeIfPresent(Bool.self, forKey: .encryptionEnabled) ?? true
        keyExchangeCompletedAt = try container.decodeIfPresent(Date.self, forKey: .keyExchangeCompletedAt)
        wasOriginalInitiator = try container.decodeIfPresent(Bool.self, forKey: .wasOriginalInitiator)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinnedOrder = try container.decodeIfPresent(Int.self, forKey: .pinnedOrder)
        notifications = try container.decodeIfPresent([SessionNotification].self, forKey: .notifications) ?? []
    }
}

struct SessionNotification: Codable {
    let id: UUID
    let receivedAt: Date
    var viewedAt: Date?
}

enum SessionStatus: String, Codable {
    case pending
    case accepted
    case closed
    case expired
}

