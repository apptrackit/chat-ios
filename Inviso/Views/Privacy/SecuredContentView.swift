//
//  SecuredContentView.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/17/25.
//

import SwiftUI

/// A wrapper view that provides security features to any content
struct SecuredContentView<Content: View>: View {
    @StateObject private var securityManager = AppSecurityManager()
    @ViewBuilder let content: Content
    
    var body: some View {
        ZStack {
            content
            
            // Privacy overlay that appears when app goes to background
            if securityManager.showPrivacyOverlay {
                PrivacyOverlayView()
                    .zIndex(999) // Ensure it appears above all other content
                    .transition(.opacity.animation(.easeInOut(duration: 0.1)))
            }

            if securityManager.isLocked {
                AuthenticationLockView(manager: securityManager)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    .zIndex(998)
            }
        }
    }
}

#Preview {
    SecuredContentView {
        Text("Protected Content")
    }
}
