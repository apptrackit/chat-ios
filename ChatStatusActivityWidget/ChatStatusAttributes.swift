//
//  ChatStatusAttributes.swift
//  ChatStatusActivityWidget
//
//  Shared ActivityKit attributes for Live Activity
//

import Foundation
import ActivityKit

@available(iOS 16.1, *)
public struct ChatStatusAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public enum Phase: String, Codable, CaseIterable { 
            case waiting = "waiting"
            case connected = "connected"
        }
        
        public var phase: Phase
        public var roomId: String
        public var title: String // "Waiting for peer" / "Peer connected"
        public var colorHex: String // "#F7C948" (yellow) / "#34C759" (green)
        public var lastUpdated: Date
        
        public init(phase: Phase, roomId: String, title: String, colorHex: String, lastUpdated: Date = Date()) {
            self.phase = phase
            self.roomId = roomId
            self.title = title
            self.colorHex = colorHex
            self.lastUpdated = lastUpdated
        }
    }
    
    // Fixed attributes for activity duration
    public var roomId: String
    
    public init(roomId: String) {
        self.roomId = roomId
    }
}