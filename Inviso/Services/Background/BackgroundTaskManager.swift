//
//  BackgroundTaskManager.swift
//  Inviso
//
//  Created by GitHub Copilot on 9/29/25.
//

import Foundation
import BackgroundTasks

/// Background task identifiers for the app
enum BackgroundTaskIdentifier {
    static let refresh = "com.apptrackit.inviso.refresh"
}

/// Manages background task scheduling and execution for maintaining minimal peer-to-peer state
/// without violating Apple's background execution policies
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    
    private init() {}
    
    /// Register background task handlers during app launch
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifier.refresh,
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    /// Schedule the next background app refresh opportunity
    /// - Parameter earliestBeginDate: The earliest date the task should begin (optional)
    func scheduleAppRefresh(earliestBeginDate: Date? = nil) {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskIdentifier.refresh)
        
        // If no date specified, schedule for ~30 minutes from now
        if let beginDate = earliestBeginDate {
            request.earliestBeginDate = beginDate
        } else {
            request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes
        }
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background refresh scheduled for: \(request.earliestBeginDate?.description ?? "immediate")")
        } catch {
            print("Failed to schedule background refresh: \(error)")
        }
    }
    
    /// Handle the background app refresh task
    /// Performs lightweight housekeeping without heavy network operations
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh
        scheduleAppRefresh(earliestBeginDate: Date(timeIntervalSinceNow: 30 * 60))
        
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        
        let operation = BackgroundRefreshOperation()
        
        // Set expiration handler to clean up if the system terminates the task
        task.expirationHandler = {
            queue.cancelAllOperations()
        }
        
        // Mark task as completed when operation finishes
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }
        
        queue.addOperation(operation)
    }
}

/// Background operation for lightweight peer state management
private class BackgroundRefreshOperation: Operation {
    override func main() {
        guard !isCancelled else { return }
        
        // Perform lightweight background housekeeping
        // This should NOT involve heavy network operations or maintaining persistent connections
        DispatchQueue.main.async {
            ChatManager.shared.backgroundRefreshPendingRooms()
        }
        
        // Brief delay to allow the work to complete
        Thread.sleep(forTimeInterval: 0.5)
    }
}
