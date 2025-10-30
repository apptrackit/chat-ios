//
//  InvisoApp.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/12/25.
//

import SwiftUI
import UserNotifications

@main
struct InvisoApp: App {
    @StateObject private var chat = ChatManager()
    @StateObject private var pushManager = PushNotificationManager.shared
    @StateObject private var onboardingManager = OnboardingManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            if onboardingManager.hasCompletedOnboarding {
                SecuredContentView {
                    ContentView()
                        .environmentObject(chat)
                        .environmentObject(pushManager)
                        .onOpenURL { url in
                            chat.handleIncomingURL(url)
                        }
                        .task {
                            // Check notification authorization status on app launch
                            await pushManager.checkAuthorizationStatus()
                        }
                }
            } else {
                OnboardingView()
            }
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set the notification center delegate
        UNUserNotificationCenter.current().delegate = PushNotificationManager.shared
        return true
    }
    
    /// Called when APNs successfully registers the device token
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationManager.shared.setDeviceToken(deviceToken)
    }
    
    /// Called when APNs registration fails
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Push] ❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

