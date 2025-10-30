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
            // Only show content when unlocked
            if !securityManager.isLocked {
                content
            }

            // App lock screen when authentication is required
            if securityManager.isLocked {
                AppLockView(securityManager: securityManager)
                    .zIndex(999)
            }
        }
    }
}

#Preview {
    SecuredContentView {
        Text("Protected Content")
    }
}
