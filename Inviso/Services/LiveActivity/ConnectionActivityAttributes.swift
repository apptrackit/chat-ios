//
//  ConnectionActivityAttributes.swift
//  Inviso
//
//  Created by GitHub Copilot on 9/28/25.
//

import Foundation
import ActivityKit

@available(iOS 16.2, *)
public struct ConnectionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var isConnected: Bool
        public var statusText: String
        public var lastUpdated: Date
    }

    public var roomName: String
}
