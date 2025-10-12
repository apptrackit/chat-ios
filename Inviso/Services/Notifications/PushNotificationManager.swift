//
//  PushNotificationManager.swift
//  Inviso
//
//  Push notification manager for APNs-based presence notifications.
//  Handles device token registration, authorization, and notification handling.
//

import Foundation
import UserNotifications
import SwiftUI
import Combine

/// Manages push notification registration and handling for the Inviso app.
/// Uses UserNotifications framework for iOS push notifications via APNs.
class PushNotificationManager: NSObject, ObservableObject {
    
    // MARK: - ObservableObject
    
    let objectWillChange = ObservableObjectPublisher()
    
    // MARK: - Singleton
    
    static let shared = PushNotificationManager()
    
    // MARK: - Published Properties
    
    /// Current push notification authorization status
    var authorizationStatus: UNAuthorizationStatus = .notDetermined {
        willSet {
            objectWillChange.send()
        }
    }
    
    /// Whether push notifications are enabled (authorized)
    var isEnabled: Bool = false {
        willSet {
            objectWillChange.send()
        }
    }
    
    /// The device token as a hex string (stored in Keychain)
    private(set) var deviceToken: String? {
        willSet {
            objectWillChange.send()
        }
    }
    
    // MARK: - Private Properties
    
    private let keychainService = KeychainService(service: "com.31b4.inviso.pushNotifications")
    private let deviceTokenKey = "apns_device_token"
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        
        // Load device token from keychain
        loadDeviceToken()
        
        // Check current authorization status
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    // MARK: - Public Methods
    
    /// Request push notification authorization from the user.
    /// Should be called when appropriate (e.g., after user action, not on app launch).
    @MainActor
    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        
        authorizationStatus = granted ? .authorized : .denied
        isEnabled = granted
        
        if granted {
            // Register for remote notifications on the main thread
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    /// Check the current authorization status without prompting the user
    @MainActor
    func checkAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        authorizationStatus = settings.authorizationStatus
        isEnabled = settings.authorizationStatus == .authorized
        
        // If already authorized, register for remote notifications to get device token
        if settings.authorizationStatus == .authorized {
            print("[Push] Notifications already authorized - registering for remote notifications")
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            print("[Push] Notification status: \(settings.authorizationStatus.rawValue)")
        }
    }
    
    /// Store the device token received from APNs
    /// Called from AppDelegate didRegisterForRemoteNotificationsWithDeviceToken
    func setDeviceToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        
        print("[Push Debug] 📥 setDeviceToken() called with token: \(tokenString.prefix(16))...")
        print("[Push Debug] Token length: \(tokenString.count) chars (expected: 64)")
        
        // Store in keychain
        do {
            try keychainService.setString(tokenString, for: deviceTokenKey)
            print("[Push Debug] ✅ Saved to keychain successfully")
            
            // Update published property on main thread
            DispatchQueue.main.async {
                self.deviceToken = tokenString
                print("[Push Debug] ✅ Set deviceToken property on main thread")
            }
            
            print("[Push] ✅ Device token registered: \(tokenString.prefix(16))...")
        } catch {
            print("[Push] ❌ Failed to save device token to keychain: \(error)")
        }
    }
    
    /// Get the current device token (if available)
    func getDeviceToken() -> String? {
        // Debug logging to diagnose token issues
        if let token = deviceToken {
            print("[Push Debug] ✅ getDeviceToken() returning: \(token.prefix(16))...")
            print("[Push Debug] Property deviceToken is set: YES")
        } else {
            print("[Push Debug] ❌ getDeviceToken() returning: nil")
            print("[Push Debug] Property deviceToken is set: NO")
            
            // Check if it's in keychain but not in memory
            if let keychainToken = keychainService.string(for: deviceTokenKey) {
                print("[Push Debug] ⚠️ FOUND in keychain: \(keychainToken.prefix(16))... (not loaded to memory!)")
            } else {
                print("[Push Debug] ⚠️ NOT FOUND in keychain either")
            }
        }
        
        return deviceToken
    }
    
    /// Load device token from keychain (called on init)
    private func loadDeviceToken() {
        print("[Push Debug] 🔄 loadDeviceToken() called (on init)")
        
        if let token = keychainService.string(for: deviceTokenKey) {
            deviceToken = token
            print("[Push] Loaded device token from keychain: \(token.prefix(16))...")
            print("[Push Debug] ✅ deviceToken property set from keychain")
        } else {
            print("[Push] No device token found in keychain")
            print("[Push Debug] ℹ️ This is normal on first launch - token will be registered when notifications enabled")
            print("[Push Debug] ℹ️ Check notification authorization status to see if you need to enable notifications")
        }
    }
    
    /// Clear the device token (e.g., on logout or when user disables notifications)
    func clearDeviceToken() {
        do {
            try keychainService.delete(account: deviceTokenKey)
            
            DispatchQueue.main.async {
                self.deviceToken = nil
            }
            
            print("[Push] Device token cleared")
        } catch {
            print("[Push] Failed to clear device token: \(error)")
        }
    }
    
    /// Handle notification tap when app is opened from a push notification
    /// Extracts the roomId from the notification and posts a notification for ChatManager to handle
    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        guard let roomId = userInfo["roomId"] as? String else {
            print("[Push] ⚠️ No roomId in notification payload")
            return
        }
        
        print("[Push] 📱 User tapped notification for room: \(roomId.prefix(8))...")
        
        // Post notification for ChatManager to handle
        NotificationCenter.default.post(
            name: .pushNotificationTapped,
            object: nil,
            userInfo: ["roomId": roomId]
        )
    }
    
    /// Helper function to look up room name from ChatManager sessions
    /// This should be called from outside (e.g., AppDelegate) with access to ChatManager
    static func getRoomName(forRoomId roomId: String, sessions: [ChatSession]) -> String? {
        return sessions.first(where: { $0.roomId == roomId })?.name
    }
    
    /// Helper function to look up session from ChatManager sessions
    static func getSession(forRoomId roomId: String, sessions: [ChatSession]) -> ChatSession? {
        return sessions.first(where: { $0.roomId == roomId })
    }
    
    /// Open iOS Settings app to the notification settings for this app
    @MainActor
    func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    
    /// Called when a notification is received while the app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        
        if let roomId = userInfo["roomId"] as? String {
            // Try to get room name for better logging
            let roomName = getRoomName(forRoomId: roomId) ?? "Unnamed Room"
            print("[Push] 📬 Notification received (foreground): \(roomName) (roomId: \(roomId.prefix(8))...)")
        } else {
            print("[Push] 📬 Notification received (foreground, no roomId)")
        }
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Called when user taps on a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Log with room name if available
        if let roomId = userInfo["roomId"] as? String {
            let roomName = getRoomName(forRoomId: roomId) ?? "Unnamed Room"
            print("[Push] 🎯 User tapped notification: \(roomName) (roomId: \(roomId.prefix(8))...)")
        }
        
        handleNotificationTap(userInfo: userInfo)
        completionHandler()
    }
    
    /// Get room name from UserDefaults (sessions storage)
    /// This is a lightweight way to access session data without ChatManager dependency
    private func getRoomName(forRoomId roomId: String) -> String? {
        guard let data = UserDefaults.standard.data(forKey: "sessions"),
              let sessions = try? JSONDecoder().decode([ChatSession].self, from: data) else {
            return nil
        }
        
        return sessions.first(where: { $0.roomId == roomId })?.name
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a push notification is tapped
    /// UserInfo contains: ["roomId": String]
    static let pushNotificationTapped = Notification.Name("pushNotificationTapped")
}
