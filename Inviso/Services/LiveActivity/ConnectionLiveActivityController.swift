//
//  ConnectionLiveActivityController.swift
//  Inviso
//
//  Created by GitHub Copilot on 9/28/25.
//

import Foundation
import ActivityKit

/// Wraps ActivityKit live activities for the peer-to-peer connection indicator.
@MainActor
final class ConnectionLiveActivityController {
    static let shared = ConnectionLiveActivityController()

    private var activityToken: Any?

    private init() {}

    func update(roomName: String, isConnected: Bool) {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ConnectionAttributes(roomName: roomName)
        let state = ConnectionAttributes.ContentState(
            isConnected: isConnected,
            statusText: isConnected ? "Connected" : "Waiting",
            lastUpdated: Date()
        )

        if let existing = activityToken as? Activity<ConnectionAttributes> {
            Task {
                await existing.update(using: state)
            }
        } else {
            Task {
                do {
                    let activity = try Activity.request(
                        attributes: attributes,
                        content: ActivityContent(state: state, staleDate: nil)
                    )
                    activityToken = activity
                } catch {
                    print("LiveActivity request error: \(error)")
                }
            }
        }
    }

    func end() {
        guard #available(iOS 16.2, *) else { return }
        guard let existing = activityToken as? Activity<ConnectionAttributes> else { return }
        Task {
            await existing.end(dismissalPolicy: .immediate)
            activityToken = nil
        }
    }
}
