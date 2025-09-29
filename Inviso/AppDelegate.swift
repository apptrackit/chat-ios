//
//  AppDelegate.swift
//  Inviso
//
//  Created by GitHub Copilot on 9/29/25.
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Register background task handlers
        BackgroundTaskManager.shared.register()
        
        // Request notification permissions
        LocalNotificationManager.shared.requestAuthorization()
        
        return true
    }
    
    // MARK: - Background Tasks
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Schedule background refresh when app enters background
        BackgroundTaskManager.shared.scheduleAppRefresh()
        
        // Prepare ChatManager for background mode
        DispatchQueue.main.async {
            ChatManager.shared.prepareForBackground()
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Resume ChatManager when coming back to foreground
        DispatchQueue.main.async {
            ChatManager.shared.resumeFromBackground()
        }
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Clear notification badge when app becomes active
        application.applicationIconBadgeNumber = 0
        
        // Also clear delivered notifications since user is now active
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
