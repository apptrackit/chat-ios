//
//  MessageCleanupService.swift
//  Inviso
//
//  Background service for cleaning up expired messages
//  Runs on app launch, when entering rooms, and periodically
//
//  Created by GitHub Copilot on 10/26/25.
//

import Foundation
import UIKit
import Combine

/// Service that automatically deletes expired messages
final class MessageCleanupService {
    static let shared = MessageCleanupService()
    
    private let storage = MessageStorageManager.shared
    private var cleanupTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // Cleanup interval (5 minutes)
    private let cleanupInterval: TimeInterval = 300
    
    private init() {
        setupAppLifecycleObservers()
    }
    
    // MARK: - Public API
    
    /// Start periodic cleanup timer
    func startPeriodicCleanup() {
        stopPeriodicCleanup() // Stop existing timer if any
        
        print("[MessageCleanup] Starting periodic cleanup (every \(Int(cleanupInterval/60)) minutes)")
        
        cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: cleanupInterval,
            repeats: true
        ) { [weak self] _ in
            self?.performCleanup()
        }
        
        // Also run immediately
        performCleanup()
    }
    
    /// Stop periodic cleanup timer
    func stopPeriodicCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        print("[MessageCleanup] Stopped periodic cleanup")
    }
    
    /// Manually trigger cleanup
    func performCleanup() {
        guard storage.isUnlocked else {
            print("[MessageCleanup] ⚠️ Storage locked, skipping cleanup")
            return
        }
        
        print("[MessageCleanup] 🧹 Running cleanup...")
        
        do {
            try storage.cleanupExpiredMessages()
        } catch {
            print("[MessageCleanup] ❌ Cleanup failed: \(error)")
        }
    }
    
    /// Delete all messages for a specific session
    func deleteSessionMessages(_ sessionId: UUID) {
        print("[MessageCleanup] 🗑️ Deleting all messages for session \(sessionId.uuidString.prefix(8))")
        
        do {
            try storage.deleteMessages(for: sessionId)
        } catch {
            print("[MessageCleanup] ❌ Failed to delete messages: \(error)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func setupAppLifecycleObservers() {
        // Clean up when app becomes active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.performCleanup()
            }
            .store(in: &cancellables)
        
        // Stop timer when app enters background
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.stopPeriodicCleanup()
            }
            .store(in: &cancellables)
        
        // Restart timer when app enters foreground
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.startPeriodicCleanup()
            }
            .store(in: &cancellables)
    }
}
