//
//  LiveActivityManager.swift
//  Inviso
//
//  Created by GitHub Copilot on 10/18/25.
//

import Foundation
import ActivityKit
import SwiftUI
import Combine

// MARK: - Live Activity Attributes (Shared with Widget Extension)

/// Waiting Status
enum WaitingStatus: String, Codable, Hashable {
    case waiting = "waiting"
    case connected = "connected"
}

/// Live Activity Attributes - Must match InvisoLiveActivity target
struct InvisoLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var roomName: String
        var status: WaitingStatus
        var startTime: Date
    }
    
    var roomId: String
}

// MARK: - Live Activity Manager

/// Manager for handling Live Activity lifecycle
/// Starts Live Activity when user backgrounds app while waiting in a room
/// Updates Live Activity when peer joins (via push notification)
@available(iOS 16.2, *)
@MainActor
class LiveActivityManager: ObservableObject {
    
    static let shared = LiveActivityManager()
    
    // MARK: - Properties
    
    @Published private(set) var currentActivity: Activity<InvisoLiveActivityAttributes>?
    @Published private(set) var isActivityActive: Bool = false
    
    private let appGroupId = "group.com.31b4.inviso"
    private let activityIdKey = "live_activity_id"
    private let activityRoomIdKey = "live_activity_room_id"
    
    private init() {
        // Restore active activity on init
        Task {
            await restoreActiveActivity()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start a Live Activity for the given room
    /// Only starts if user is waiting alone in the room
    func startActivity(roomId: String, roomName: String) async {
        // Check if ActivityKit is available
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] ❌ Live Activities not enabled by user")
            return
        }
        
        // End any existing activity first
        if currentActivity != nil {
            await endActivity()
        }
        
        let attributes = InvisoLiveActivityAttributes(roomId: roomId)
        let contentState = InvisoLiveActivityAttributes.ContentState(
            roomName: roomName,
            status: .waiting,
            startTime: Date()
        )
        
        do {
            let activity = try Activity<InvisoLiveActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            
            currentActivity = activity
            isActivityActive = true
            
            // Save to App Group for Notification Service Extension to check
            saveActivityToAppGroup(activityId: activity.id, roomId: roomId)
            
            print("[LiveActivity] ✅ Started activity for room: \(roomId.prefix(8))... (\(roomName))")
            
            // Monitor activity state
            Task {
                await monitorActivityState(activity: activity)
            }
            
            // Auto-dismiss after 30 minutes
            Task {
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000) // 30 minutes
                await endActivityIfStillWaiting(roomId: roomId)
            }
            
        } catch {
            print("[LiveActivity] ❌ Failed to start activity: \(error)")
        }
    }
    
    /// Update Live Activity to "connected" state when peer joins
    /// Called from Notification Service Extension via App Group update
    func updateActivityToConnected(roomId: String) async {
        guard let activity = currentActivity,
              activity.attributes.roomId == roomId else {
            print("[LiveActivity] ⚠️ No matching activity to update for room: \(roomId.prefix(8))")
            return
        }
        
        let updatedState = InvisoLiveActivityAttributes.ContentState(
            roomName: activity.content.state.roomName,
            status: .connected,
            startTime: activity.content.state.startTime
        )
        
        do {
            await activity.update(
                .init(state: updatedState, staleDate: nil)
            )
            print("[LiveActivity] ✅ Updated activity to CONNECTED for room: \(roomId.prefix(8))")
            
            // Auto-dismiss after 5 seconds when connected
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                await endActivity()
            }
            
        } catch {
            print("[LiveActivity] ❌ Failed to update activity: \(error)")
        }
    }
    
    /// End the current Live Activity
    func endActivity() async {
        guard let activity = currentActivity else {
            print("[LiveActivity] ⚠️ No activity to end")
            return
        }
        
        await endActivity(activity)
    }
    
    /// End activity for a specific room (if it matches)
    func endActivityForRoom(_ roomId: String) async {
        guard let activity = currentActivity,
              activity.attributes.roomId == roomId else {
            print("[LiveActivity] ⚠️ Activity room mismatch, not ending")
            return
        }
        
        await endActivity(activity)
    }
    
    /// Check if there's an active Live Activity for the given room
    func hasActiveActivity(for roomId: String) -> Bool {
        guard let activity = currentActivity else { return false }
        return activity.attributes.roomId == roomId && activity.activityState == .active
    }
    
    /// Get the room ID of the current active Live Activity
    func getCurrentActivityRoomId() -> String? {
        return currentActivity?.attributes.roomId
    }
    
    // MARK: - Private Methods
    
    private func endActivity(_ activity: Activity<InvisoLiveActivityAttributes>) async {
        // End the activity immediately
        await activity.end(dismissalPolicy: .immediate)
        
        currentActivity = nil
        isActivityActive = false
        
        // Clear from App Group
        clearActivityFromAppGroup()
        
        print("[LiveActivity] ✅ Ended activity for room: \(activity.attributes.roomId.prefix(8))")
    }
    
    private func endActivityIfStillWaiting(roomId: String) async {
        guard let activity = currentActivity,
              activity.attributes.roomId == roomId,
              activity.content.state.status == WaitingStatus.waiting else {
            return
        }
        
        print("[LiveActivity] ⏰ Auto-dismissing activity after 30 min timeout")
        await endActivity(activity)
    }
    
    private func restoreActiveActivity() async {
        // Try to restore any existing activity from ActivityKit
        for activity in Activity<InvisoLiveActivityAttributes>.activities {
            if activity.activityState == .active {
                currentActivity = activity
                isActivityActive = true
                print("[LiveActivity] ✅ Restored active activity for room: \(activity.attributes.roomId.prefix(8))")
                
                // Monitor this activity
                Task {
                    await monitorActivityState(activity: activity)
                }
                break
            }
        }
    }
    
    private func monitorActivityState(activity: Activity<InvisoLiveActivityAttributes>) async {
        // Monitor activity state changes (user dismissal, etc.)
        for await state in activity.activityStateUpdates {
            print("[LiveActivity] 🔄 Activity state changed: \(state)")
            
            if state == .dismissed || state == .ended {
                if currentActivity?.id == activity.id {
                    currentActivity = nil
                    isActivityActive = false
                    clearActivityFromAppGroup()
                }
                break
            }
        }
    }
    
    // MARK: - App Group Storage
    
    private func saveActivityToAppGroup(activityId: String, roomId: String) {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            print("[LiveActivity] ❌ Failed to access App Group")
            return
        }
        
        sharedDefaults.set(activityId, forKey: activityIdKey)
        sharedDefaults.set(roomId, forKey: activityRoomIdKey)
        sharedDefaults.synchronize()
        
        print("[LiveActivity] 💾 Saved to App Group: activityId=\(activityId.prefix(8))..., roomId=\(roomId.prefix(8))...")
    }
    
    private func clearActivityFromAppGroup() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            return
        }
        
        sharedDefaults.removeObject(forKey: activityIdKey)
        sharedDefaults.removeObject(forKey: activityRoomIdKey)
        sharedDefaults.synchronize()
        
        print("[LiveActivity] 🗑️ Cleared from App Group")
    }
    
    /// Get active Live Activity info from App Group (used by Notification Service Extension)
    static func getActiveActivityInfo(appGroupId: String) -> (activityId: String, roomId: String)? {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupId),
              let activityId = sharedDefaults.string(forKey: "live_activity_id"),
              let roomId = sharedDefaults.string(forKey: "live_activity_room_id") else {
            return nil
        }
        
        return (activityId, roomId)
    }
}
