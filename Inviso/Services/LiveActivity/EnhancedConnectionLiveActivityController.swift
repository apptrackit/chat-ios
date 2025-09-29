//
//  EnhancedConnectionLiveActivityController.swift
//  Inviso
//
//  Created by GitHub Copilot on 9/28/25.
//

import Foundation
import ActivityKit

@available(iOS 16.1, *)
@MainActor
public enum LiveActivityManager {
    
    // MARK: - Public Interface
    
    /// Start a Live Activity for a room in waiting state
    public static func start(roomId: String, title: String = "Waiting for peer") async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { 
            print("🟡 Live Activities not enabled by user")
            return 
        }
        
        print("🧪 Starting Live Activity for room: \(roomId)")
        print("🧪 Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        print("🧪 iOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        
        // End any existing activity for this room first
        await end(roomId: roomId)
        
        let attributes = ChatStatusAttributes(roomId: roomId)
        let content = ChatStatusAttributes.ContentState(
            phase: .waiting,
            roomId: roomId,
            title: title,
            colorHex: "#F7C948" // Yellow
        )
        
        do {
            let activity = try Activity<ChatStatusAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: content, staleDate: nil)
                // No pushType needed for local-only implementation
            )
            print("🟡 Live Activity started successfully for room: \(roomId)")
            print("🟡 Activity ID: \(activity.id)")
        } catch {
            print("❌ Failed to start Live Activity: \(error)")
            
            // Enhanced error diagnostics
            print("❌ Error details: \(error.localizedDescription)")
            print("❌ Error type: \(type(of: error))")
            
            // Check for specific ActivityKit errors
            if let nsError = error as NSError? {
                print("❌ Error domain: \(nsError.domain)")
                print("❌ Error code: \(nsError.code)")
                print("❌ Error userInfo: \(nsError.userInfo)")
            }
            
            // Additional diagnostics
            print("🔍 Current active activities: \(Activity<ChatStatusAttributes>.activities.count)")
            print("🔍 Activities enabled: \(ActivityAuthorizationInfo().areActivitiesEnabled)")
        }
    }
    
    /// Update the Live Activity to connected state (green)
    public static func updateToConnected(roomId: String) async {
        let content = ChatStatusAttributes.ContentState(
            phase: .connected,
            roomId: roomId,
            title: "Peer connected",
            colorHex: "#34C759" // Green
        )
        
        await updateActivity(roomId: roomId, content: content)
        print("🟢 Live Activity updated to connected for room: \(roomId)")
    }
    
    /// Update the Live Activity back to waiting state (yellow)
    public static func updateToWaiting(roomId: String) async {
        let content = ChatStatusAttributes.ContentState(
            phase: .waiting,
            roomId: roomId,
            title: "Waiting for peer",
            colorHex: "#F7C948" // Yellow
        )
        
        await updateActivity(roomId: roomId, content: content)
        print("🟡 Live Activity updated to waiting for room: \(roomId)")
    }
    
    /// End the Live Activity for a specific room
    public static func end(roomId: String) async {
        for activity in Activity<ChatStatusAttributes>.activities {
            if activity.attributes.roomId == roomId {
                await activity.end(nil, dismissalPolicy: .immediate)
                print("⭕ Live Activity ended for room: \(roomId)")
                return
            }
        }
    }
    
    /// End all active Live Activities
    public static func endAll() async {
        for activity in Activity<ChatStatusAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        print("⭕ All Live Activities ended")
    }
    
    // MARK: - Internal Helpers
    
    private static func updateActivity(roomId: String, content: ChatStatusAttributes.ContentState) async {
        for activity in Activity<ChatStatusAttributes>.activities {
            if activity.attributes.roomId == roomId {
                let newState = ActivityContent(state: content, staleDate: nil)
                await activity.update(newState)
                return
            }
        }
        print("⚠️ No active Live Activity found for room: \(roomId)")
    }
    
    /// Check if Live Activities are available and enabled
    public static var isAvailable: Bool {
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    
    /// Get count of active Live Activities
    public static var activeCount: Int {
        return Activity<ChatStatusAttributes>.activities.count
    }
}