//
//  BackgroundTestingUtility.swift
//  Inviso
//
//  Created by GitHub Copilot on 9/29/25.
//

import Foundation
import BackgroundTasks

#if DEBUG
/// Utility for testing background functionality during development
/// Use this in development builds to simulate background app refresh
final class BackgroundTestingUtility {
    static let shared = BackgroundTestingUtility()
    
    private init() {}
    
    /// Simulate a background app refresh for testing
    /// Call this from your UI during development to test background behavior
    func simulateBackgroundRefresh() {
        print("🧪 Simulating background app refresh")
        
        // Simulate the app going to background
        ChatManager.shared.prepareForBackground()
        
        // Wait a moment, then simulate background refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            ChatManager.shared.backgroundRefreshPendingRooms()
            
            // Simulate coming back to foreground
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                ChatManager.shared.resumeFromBackground()
            }
        }
    }
    
    /// Schedule immediate background task for testing
    /// Use with Xcode's Debug > Simulate Background Fetch
    func scheduleImmediateBackgroundTask() {
        BackgroundTaskManager.shared.scheduleAppRefresh(earliestBeginDate: Date())
        print("🧪 Scheduled immediate background task - use Xcode > Debug > Simulate Background Fetch")
    }
    
    /// Simulate a peer connection notification for testing
    func simulatePeerConnectedNotification(roomId: String = "test-room") {
        print("🧪 Simulating peer connected notification for room: \(roomId)")
        LocalNotificationManager.shared.notifyPeerConnected(roomId: roomId)
    }
    
    /// Send a test notification regardless of app state
    func sendTestNotification() {
        print("🧪 Sending test notification")
        LocalNotificationManager.shared.sendTestNotification(
            title: "Test Notification",
            body: "This notification should appear regardless of app state"
        )
    }
    
    /// Simulate a test message notification
    func simulateMessageNotification(message: String = "Hello! This is a test message from your chat partner.") {
        print("🧪 Simulating message notification: \(message)")
        LocalNotificationManager.shared.notifyNewMessage(text: message, roomId: "test-room")
    }
    
    /// Simulate a peer disconnection notification for testing  
    func simulatePeerDisconnectedNotification(roomId: String = "test-room") {
        print("🧪 Simulating peer disconnected notification for room: \(roomId)")
        LocalNotificationManager.shared.notifyPeerDisconnected(roomId: roomId)
    }
    
    /// Clear all test notifications
    func clearTestNotifications() {
        print("🧪 Clearing all test notifications")
        LocalNotificationManager.shared.clearAllNotifications()
    }
    
    /// Simulate complete peer connection flow for testing
    func simulateCompletePeerConnectionFlow() {
        print("🧪 Starting complete peer connection simulation")
        
        // Step 1: Force a test notification first
        LocalNotificationManager.shared.sendTestNotification(
            title: "Peer Connection Test",
            body: "Testing complete peer connection flow"
        )
        
        // Step 2: Simulate the actual peer connection event
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let testRoomId = "test-room-\(UUID().uuidString.prefix(8))"
            print("🧪 Simulating peer joined for room: \(testRoomId)")
            
            // Directly call the ChatManager's peer event handler
            ChatManager.shared.onPeerJoined()
        }
    }
}
#endif