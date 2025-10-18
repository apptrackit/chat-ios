//
//  NotificationService.swift
//  InvisoNotificationService
//
//  Created by Bence Szilagyi on 10/12/25.
//

import UserNotifications
import ActivityKit

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
        
        NSLog("🔔 [NotificationService] Notification for roomId: \(roomId)")
        
        // CHECK: Is there an active Live Activity for this room?
        if #available(iOS 16.2, *), let (_, liveActivityRoomId) = getActiveLiveActivity() {
            if liveActivityRoomId == roomId {
                NSLog("🔔 [NotificationService] ✅ Live Activity active for this room - updating to CONNECTED and suppressing APN")
                
                // Update Live Activity to "connected" state
                updateLiveActivityToConnected(roomId: roomId)
                
                // Track notification (for app sync)
                trackNotification(roomId: roomId, receivedAt: Date())
                
                // SUPPRESS APN - don't show notification card
                // Deliver empty notification (user will see Live Activity update instead)
                bestAttemptContent.title = ""
                bestAttemptContent.body = ""
                bestAttemptContent.sound = nil
                
                // Still update badge count
                let totalBadgeCount = calculateTotalBadgeCount()
                bestAttemptContent.badge = NSNumber(value: totalBadgeCount)
                
                contentHandler(bestAttemptContent)
                return
            } else {
                NSLog("🔔 [NotificationService] Live Activity exists but for different room (\(liveActivityRoomId.prefix(8))...) - showing normal APN")
            }
        }
        
        NSLog("🔔 [NotificationService] Looking up room name for roomId: \(roomId)")
        
        // IMPORTANT: Track this notification in App Group storage
        trackNotification(roomId: roomId, receivedAt: Date())
        
        // Calculate and set accumulated badge count
        let totalBadgeCount = calculateTotalBadgeCount()
        bestAttemptContent.badge = NSNumber(value: totalBadgeCount)
        NSLog("🔔 [NotificationService] Set badge to: \(totalBadgeCount)")
        
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
    
    /// Calculate total badge count from App Group storage
    /// This counts all pending notifications that haven't been synced yet
    /// PLUS the current iOS badge count (so it continues accumulating)
    private func calculateTotalBadgeCount() -> Int {
        let appGroupId = "group.com.31b4.inviso"
        let pendingNotificationsKey = "pending_notifications"
        let currentBadgeKey = "current_badge_count"
        
        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            NSLog("🔔 [NotificationService] ❌ Failed to access App Group for badge count")
            return 1 // Fallback to 1
        }
        
        // Get current badge count (set by main app when it last updated)
        let currentBadge = sharedDefaults.integer(forKey: currentBadgeKey)
        
        // Get pending notifications count (notifications received while app was closed)
        let pendingNotifications = sharedDefaults.array(forKey: pendingNotificationsKey) as? [[String: Any]] ?? []
        let pendingCount = pendingNotifications.count
        
        // New badge = current badge (when app closed) + pending count
        // The pending count already includes this notification (we tracked it before calling this)
        let newBadge = currentBadge + pendingCount
        
        NSLog("🔔 [NotificationService] Current badge: \(currentBadge), Pending: \(pendingCount), New badge: \(newBadge)")
        return max(newBadge, 1) // Ensure at least 1
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

// MARK: - Live Activity Support

extension NotificationService {
    
    /// Get active Live Activity info from App Group
    @available(iOS 16.2, *)
    private func getActiveLiveActivity() -> (activityId: String, roomId: String)? {
        let appGroupId = "group.com.31b4.inviso"
        let activityIdKey = "live_activity_id"
        let activityRoomIdKey = "live_activity_room_id"
        
        guard let sharedDefaults = UserDefaults(suiteName: appGroupId),
              let activityId = sharedDefaults.string(forKey: activityIdKey),
              let roomId = sharedDefaults.string(forKey: activityRoomIdKey) else {
            NSLog("🔔 [NotificationService] No active Live Activity found in App Group")
            return nil
        }
        
        NSLog("🔔 [NotificationService] Found active Live Activity: activityId=\(activityId.prefix(8))..., roomId=\(roomId.prefix(8))...")
        return (activityId, roomId)
    }
    
    /// Update Live Activity to "connected" state
    /// This signals to the main app that the Live Activity needs updating
    @available(iOS 16.2, *)
    private func updateLiveActivityToConnected(roomId: String) {
        let appGroupId = "group.com.31b4.inviso"
        let updateKey = "live_activity_update_\(roomId)"
        
        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            NSLog("🔔 [NotificationService] ❌ Failed to access App Group for Live Activity update")
            return
        }
        
        // Signal to main app to update Live Activity (fallback)
        let update: [String: Any] = [
            "status": "connected",
            "timestamp": Date().timeIntervalSince1970
        ]
        sharedDefaults.set(update, forKey: updateKey)
        sharedDefaults.synchronize()
        
        NSLog("🔔 [NotificationService] ✅ Signaled Live Activity update for room: \(roomId.prefix(8))...")
        
        // Attempt to update the Live Activity immediately so user sees status change without opening the app
        if #available(iOS 16.2, *) {
            updateLiveActivityDirectly(roomId: roomId)
        }
    }
}

#if canImport(ActivityKit)
// MARK: - ActivityKit Helpers

@available(iOS 16.2, *)
extension NotificationService {
    private func updateLiveActivityDirectly(roomId: String) {
        Task {
            let activities = Activity<InvisoLiveActivityAttributes>.activities
            guard let activity = activities.first(where: { $0.attributes.roomId == roomId }) else {
                NSLog("🔔 [NotificationService] ⚠️ No matching Live Activity instance found for room: \(roomId.prefix(8))...")
                return
            }
            
            let currentState = activity.content.state
            let updatedState = InvisoLiveActivityAttributes.ContentState(
                roomName: currentState.roomName,
                status: .connected,
                startTime: currentState.startTime
            )
            
            do {
                try await activity.update(.init(state: updatedState, staleDate: nil))
                NSLog("🔔 [NotificationService] ✅ Live Activity updated to CONNECTED for room: \(roomId.prefix(8))...")
                
                // Auto-dismiss after short delay to match main app behavior
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await activity.end(dismissalPolicy: .immediate)
            } catch {
                NSLog("🔔 [NotificationService] ❌ Failed to update Live Activity: \(String(describing: error))")
            }
        }
    }
}

// Duplicate the Activity Attributes here so the extension can compile without a shared module
@available(iOS 16.1, *)
struct InvisoLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var roomName: String
        var status: WaitingStatus
        var startTime: Date
    }
    var roomId: String
}

enum WaitingStatus: String, Codable, Hashable {
    case waiting
    case connected
}
#endif

