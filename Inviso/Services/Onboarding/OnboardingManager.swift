//
//  OnboardingManager.swift
//  Inviso
//
//  Manages the onboarding state and completion tracking.
//

import Foundation
import Combine

/// Tracks whether the user has completed onboarding
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()
    
    @Published private(set) var hasCompletedOnboarding: Bool
    
    private let storeKey = "onboarding.completed.v1"
    
    private init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: storeKey)
    }
    
    /// Mark onboarding as completed
    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: storeKey)
    }
    
    /// Reset onboarding state (for testing or user reset)
    func resetOnboarding() {
        hasCompletedOnboarding = false
        UserDefaults.standard.set(false, forKey: storeKey)
    }
}
