//
//  PrivacyOverlayView.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/17/25.
//

import SwiftUI

/// A full-screen black overlay that protects app content when backgrounded
struct PrivacyOverlayView: View {
    var body: some View {
        Rectangle()
            .fill(Color.black)
            .ignoresSafeArea(.all)
            .allowsHitTesting(false) // Allows touches to pass through when overlay is hidden
    }
}

#Preview {
    PrivacyOverlayView()
}
