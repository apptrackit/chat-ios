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
}

struct ChatSession: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String?
    var code: String // 6-digit join code
    var roomId: String? // backend room id once accepted
    var createdAt: Date
    var expiresAt: Date?
    var status: SessionStatus
    var isCreatedByMe: Bool
    var ephemeralDeviceId: String // Unique per-session identifier for privacy

    init(id: UUID = UUID(), name: String? = nil, code: String, roomId: String? = nil, createdAt: Date = Date(), expiresAt: Date? = nil, status: SessionStatus = .pending, isCreatedByMe: Bool = true, ephemeralDeviceId: String = UUID().uuidString) {
        self.id = id
        self.name = name
        self.code = code
        self.roomId = roomId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.status = status
        self.isCreatedByMe = isCreatedByMe
        self.ephemeralDeviceId = ephemeralDeviceId
    }

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        return "Room \(code)"
    }
}
