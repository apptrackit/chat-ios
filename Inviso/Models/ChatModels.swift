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

    init(id: UUID = UUID(), name: String? = nil, code: String, roomId: String? = nil, createdAt: Date = Date(), expiresAt: Date? = nil, lastActivityDate: Date = Date(), firstConnectedAt: Date? = nil, closedAt: Date? = nil, status: SessionStatus = .pending, isCreatedByMe: Bool = true, ephemeralDeviceId: String = UUID().uuidString) {
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
    }
    
    // Custom Codable for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, name, code, roomId, createdAt, expiresAt, lastActivityDate, firstConnectedAt, closedAt, status, isCreatedByMe, ephemeralDeviceId
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
    }

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        return "Room \(code)"
    }
}
