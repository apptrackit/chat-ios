//
//  LocalNotificationManager.swift
//  Inviso
//
//  Created by GitHub Copilot on 9/29/25.
//

import Foundation
import UserNotifications
import UIKit

/// Manages local notifications for peer-to-peer events without requiring APNs or remote push
final class LocalNotificationManager: NSObject {
    static let shared = LocalNotificationManager()
    
    override init() {
        super.init()
    }
    
    /// Request notification authorization from the user
    /// Call this during app launch or when first needed
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Notification permission error: \(error)")
                } else {
                    print("Notification permission granted: \(granted)")
                }
            }
        }
        
        // Set delegate to handle foreground presentation
        UNUserNotificationCenter.current().delegate = self
    }
    
    /// Fire a local notification when a peer connects to the room
    /// - Parameter roomId: The room ID where the peer connected
    func notifyPeerConnected(roomId: String) {
        let appState = UIApplication.shared.applicationState
        print("🔔 Checking notification - App state: \(appState.rawValue) (0=active, 1=inactive, 2=background)")
        
        // Send notification if app is not active OR if explicitly backgrounded
        let shouldNotify = appState != .active
        print("🔔 Should notify: \(shouldNotify)")
        
        if shouldNotify {
            let content = UNMutableNotificationContent()
            content.title = "Peer Connected"
            content.body = "Someone joined your chat room. Tap to continue."
            content.sound = .default
            content.badge = 1
            
            // Add room information for handling when user taps
            content.userInfo = [
                "type": "peer_connected",
                "roomId": roomId,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            // Create immediate notification (no trigger = immediate delivery)
            let request = UNNotificationRequest(
                identifier: "peer-connected-\(roomId)-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ Failed to schedule local notification: \(error)")
                } else {
                    print("✅ Local notification scheduled for peer connection in room: \(roomId)")
                }
            }
        } else {
            print("🔔 App is active, skipping notification")
        }
    }
    
    /// Fire a local notification when a peer disconnects from the room
    /// - Parameter roomId: The room ID where the peer disconnected
    func notifyPeerDisconnected(roomId: String) {
        let appState = UIApplication.shared.applicationState
        print("🔔 Peer disconnected - App state: \(appState.rawValue)")
        
        // Send notification if app is not active
        let shouldNotify = appState != .active
        
        if shouldNotify {
            let content = UNMutableNotificationContent()
            content.title = "Peer Disconnected"
            content.body = "Your chat partner has left the room."
            content.sound = .default
            content.badge = 0
            
            content.userInfo = [
                "type": "peer_disconnected",
                "roomId": roomId,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            let request = UNNotificationRequest(
                identifier: "peer-disconnected-\(roomId)-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ Failed to schedule peer disconnection notification: \(error)")
                } else {
                    print("✅ Peer disconnection notification scheduled")
                }
            }
        } else {
            print("🔔 App is active, skipping disconnection notification")
        }
    }
    
    /// Clear all pending notifications
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    
    /// Clear notifications for a specific room
    /// - Parameter roomId: The room ID to clear notifications for
    func clearNotifications(for roomId: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiersToRemove = requests
                .filter { $0.content.userInfo["roomId"] as? String == roomId }
                .map { $0.identifier }
            
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        }
        
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let identifiersToRemove = notifications
                .filter { $0.request.content.userInfo["roomId"] as? String == roomId }
                .map { $0.request.identifier }
            
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension LocalNotificationManager: UNUserNotificationCenterDelegate {
    /// Present notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even when app is in foreground
        completionHandler([.banner, .list, .sound])
    }
    
    /// Handle notification taps
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        if let type = userInfo["type"] as? String,
           let roomId = userInfo["roomId"] as? String {
            
            DispatchQueue.main.async {
                switch type {
                case "peer_connected":
                    // Navigate user to the chat room when they tap the notification
                    self.handlePeerConnectedNotificationTap(roomId: roomId)
                case "new_message":
                    // Navigate user to the chat room for new message
                    self.handleMessageNotificationTap(roomId: roomId)
                case "peer_disconnected":
                    // Handle peer disconnection notification tap if needed
                    break
                default:
                    break
                }
            }
        }
        
        completionHandler()
    }
    
    private func handlePeerConnectedNotificationTap(roomId: String) {
        // Notify ChatManager to join this room when user taps notification
        ChatManager.shared.handleNotificationTap(for: roomId)
    }
    
    private func handleMessageNotificationTap(roomId: String) {
        // Notify ChatManager to join this room when user taps message notification
        ChatManager.shared.handleNotificationTap(for: roomId)
    }
    
    /// Force send a test notification regardless of app state (for testing)
    func sendTestNotification(title: String = "Test Notification", body: String = "This is a test notification") {
        print("🧪 Sending test notification regardless of app state")
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1
        
        content.userInfo = [
            "type": "test",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send test notification: \(error)")
            } else {
                print("✅ Test notification sent successfully")
            }
        }
    }
    
    /// Fire a local notification when a new message arrives
    /// - Parameters:
    ///   - text: The message text
    ///   - roomId: The room ID where the message was received
    func notifyNewMessage(text: String, roomId: String) {
        let appState = UIApplication.shared.applicationState
        print("💬 New message notification - App state: \(appState.rawValue) (0=active, 1=inactive, 2=background)")
        
        // Send notification if app is not active
        let shouldNotify = appState != .active
        print("💬 Should notify for message: \(shouldNotify)")
        
        if shouldNotify {
            let content = UNMutableNotificationContent()
            content.title = "New Message"
            
            // Truncate long messages for notification
            let truncatedText = text.count > 100 ? String(text.prefix(100)) + "..." : text
            content.body = truncatedText
            
            content.sound = .default
            
            // Increment badge count
            let currentBadge = UIApplication.shared.applicationIconBadgeNumber
            content.badge = NSNumber(value: currentBadge + 1)
            
            // Add message and room information
            content.userInfo = [
                "type": "new_message",
                "roomId": roomId,
                "messageText": text,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            // Create immediate notification
            let request = UNNotificationRequest(
                identifier: "message-\(roomId)-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ Failed to schedule message notification: \(error)")
                } else {
                    print("✅ Message notification scheduled: \"\(truncatedText)\"")
                }
            }
        } else {
            print("💬 App is active, skipping message notification")
        }
    }
}
