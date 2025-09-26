//
//  AppSecurityManager.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/17/25.
//

import SwiftUI
import Combine

/// Manages app security features including privacy overlay when app goes to background
class AppSecurityManager: ObservableObject {
    @Published var showPrivacyOverlay = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupNotificationObservers()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    private func setupNotificationObservers() {
        // Listen for app going to background
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.showPrivacyOverlay = true
            }
            .store(in: &cancellables)
        
        // Listen for app becoming active again
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.showPrivacyOverlay = false
            }
            .store(in: &cancellables)
    }
}
