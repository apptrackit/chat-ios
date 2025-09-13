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
    let text: String
    let timestamp: Date
    let isFromSelf: Bool
}
