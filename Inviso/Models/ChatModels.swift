//
//  ChatModels.swift
//  Inviso
//
//  Shared models used across chat components.
//

import Foundation

enum ConnectionStatus: String, CaseIterable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    let timestamp: Date
    let isFromSelf: Bool
    var isSystem: Bool = false
    var locationData: LocationData? = nil // Optional location data for location messages
    var voiceData: VoiceData? = nil // Optional voice data for voice messages
    
    // Message retention metadata
    var savedLocally: Bool = false // Whether this message is stored on disk
    var expiresAt: Date? = nil // When this message will be auto-deleted
    var lifetime: MessageLifetime? = nil // Retention policy for this message
    
    var isLocationMessage: Bool {
        locationData != nil
    }
    
    var isVoiceMessage: Bool {
        voiceData != nil
    }
    
    /// Check if message has expired
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
    
    /// Time remaining until expiration (for UI display)
    var timeUntilExpiration: TimeInterval? {
        guard let expiresAt = expiresAt else { return nil }
        return expiresAt.timeIntervalSinceNow
    }
}

// MARK: - Push Notification Tracking

struct SessionNotification: Identifiable, Codable, Equatable {
    let id: UUID
    let receivedAt: Date
    var viewedAt: Date?
    
    init(id: UUID = UUID(), receivedAt: Date = Date(), viewedAt: Date? = nil) {
        self.id = id
        self.receivedAt = receivedAt
        self.viewedAt = viewedAt
    }
    
    var isUnread: Bool {
        viewedAt == nil
    }
}

// MARK: - Sessions (frontend-only for now)

enum SessionStatus: String, Codable, Equatable {
    case pending
    case accepted
    case closed
    case expired
}

struct ChatSession: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String?
    var code: String // 6-digit join code
    var roomId: String? // backend room id once accepted
    var createdAt: Date
    var expiresAt: Date?
    var lastActivityDate: Date // Tracks last interaction (create, join, message) for sorting
    var firstConnectedAt: Date? // Estimated first connection time (when status became .accepted)
    var closedAt: Date? // Estimated close time (when status became .closed)
    var status: SessionStatus
    var isCreatedByMe: Bool
    var ephemeralDeviceId: String // Unique per-session identifier for privacy
    
    // Encryption status (for UI display)
    var encryptionEnabled: Bool = true // Always true for new sessions
    var keyExchangeCompletedAt: Date? // Timestamp when E2EE was established
    
    // Role persistence for reconnections
    var wasOriginalInitiator: Bool? // Tracks first assigned role to maintain consistency across rejoins
    
    // Pin feature
    var isPinned: Bool = false
    var pinnedOrder: Int? // Lower numbers appear first, nil if not pinned
    
    // Notification tracking
    var notifications: [SessionNotification] = []
    
    // Message retention settings (agreed between both peers)
    var messageLifetime: MessageLifetime = .ephemeral // Default: RAM only
    var lifetimeAgreedAt: Date? // When both peers agreed on current setting
    var lifetimeAgreedByBoth: Bool = false // True when both confirmed
    
    // Computed property for unread notification count
    var unreadNotificationCount: Int {
        notifications.filter { $0.isUnread }.count
    }
    
    // Computed property for last notification time
    var lastNotificationTime: Date? {
        notifications.last?.receivedAt
    }

    init(id: UUID = UUID(), name: String? = nil, code: String, roomId: String? = nil, createdAt: Date = Date(), expiresAt: Date? = nil, lastActivityDate: Date = Date(), firstConnectedAt: Date? = nil, closedAt: Date? = nil, status: SessionStatus = .pending, isCreatedByMe: Bool = true, ephemeralDeviceId: String = UUID().uuidString, encryptionEnabled: Bool = true, keyExchangeCompletedAt: Date? = nil, wasOriginalInitiator: Bool? = nil, isPinned: Bool = false, pinnedOrder: Int? = nil) {
        self.id = id
        self.name = name
        self.code = code
        self.roomId = roomId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.lastActivityDate = lastActivityDate
        self.firstConnectedAt = firstConnectedAt
        self.closedAt = closedAt
        self.status = status
        self.isCreatedByMe = isCreatedByMe
        self.ephemeralDeviceId = ephemeralDeviceId
        self.encryptionEnabled = encryptionEnabled
        self.keyExchangeCompletedAt = keyExchangeCompletedAt
        self.wasOriginalInitiator = wasOriginalInitiator
        self.isPinned = isPinned
        self.pinnedOrder = pinnedOrder
    }
    
    // Custom Codable for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, name, code, roomId, createdAt, expiresAt, lastActivityDate, firstConnectedAt, closedAt, status, isCreatedByMe, ephemeralDeviceId, encryptionEnabled, keyExchangeCompletedAt, wasOriginalInitiator, isPinned, pinnedOrder, notifications, messageLifetime, lifetimeAgreedAt, lifetimeAgreedByBoth
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        code = try container.decode(String.self, forKey: .code)
        roomId = try container.decodeIfPresent(String.self, forKey: .roomId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        // Fallback to createdAt if lastActivityDate is missing (backward compatibility)
        lastActivityDate = try container.decodeIfPresent(Date.self, forKey: .lastActivityDate) ?? container.decode(Date.self, forKey: .createdAt)
        firstConnectedAt = try container.decodeIfPresent(Date.self, forKey: .firstConnectedAt)
        closedAt = try container.decodeIfPresent(Date.self, forKey: .closedAt)
        status = try container.decode(SessionStatus.self, forKey: .status)
        isCreatedByMe = try container.decode(Bool.self, forKey: .isCreatedByMe)
        ephemeralDeviceId = try container.decode(String.self, forKey: .ephemeralDeviceId)
        // Encryption fields (default to true/nil for backward compatibility)
        encryptionEnabled = try container.decodeIfPresent(Bool.self, forKey: .encryptionEnabled) ?? true
        keyExchangeCompletedAt = try container.decodeIfPresent(Date.self, forKey: .keyExchangeCompletedAt)
        // Role persistence (nil for old sessions)
        wasOriginalInitiator = try container.decodeIfPresent(Bool.self, forKey: .wasOriginalInitiator)
        // Pin feature (default to false/nil for backward compatibility)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinnedOrder = try container.decodeIfPresent(Int.self, forKey: .pinnedOrder)
        // Notification tracking (default to empty array for backward compatibility)
        notifications = try container.decodeIfPresent([SessionNotification].self, forKey: .notifications) ?? []
        // Message retention (default to ephemeral for backward compatibility)
        messageLifetime = try container.decodeIfPresent(MessageLifetime.self, forKey: .messageLifetime) ?? .ephemeral
        lifetimeAgreedAt = try container.decodeIfPresent(Date.self, forKey: .lifetimeAgreedAt)
        lifetimeAgreedByBoth = try container.decodeIfPresent(Bool.self, forKey: .lifetimeAgreedByBoth) ?? false
    }

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        return "Room \(code)"
    }
}
