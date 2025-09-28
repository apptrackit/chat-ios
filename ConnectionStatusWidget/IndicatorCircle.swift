//
//  IndicatorCircle.swift
//  Inviso Live Activity Widget
//
//  Created by GitHub Copilot on 9/28/25.
//

import SwiftUI

struct IndicatorCircle: View {
    let isConnected: Bool

    var body: some View {
        Circle()
            .fill(isConnected ? Color.green : Color.yellow)
            .frame(width: 18, height: 18)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: (isConnected ? Color.green : Color.yellow).opacity(0.4), radius: 3)
            .accessibilityHidden(true)
    }
}

#Preview("Connected") {
    IndicatorCircle(isConnected: true)
        .padding()
        .background(Color.black)
}

#Preview("Waiting") {
    IndicatorCircle(isConnected: false)
        .padding()
        .background(Color.black)
}
