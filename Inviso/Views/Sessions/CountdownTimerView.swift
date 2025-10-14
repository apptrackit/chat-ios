//
//  CountdownTimerView.swift
//  Inviso
//
//  Live countdown display for session expiry times.
//

import SwiftUI
import Combine

struct CountdownTimerView: View {
    let expiresAt: Date?
    
    @State private var timeRemaining: TimeInterval = 0
    @State private var timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Text(CountdownFormatter.format(timeRemaining: timeRemaining))
            .font(.caption.monospacedDigit())
            .foregroundColor(colorForTimeRemaining)
            .onAppear { updateTimeRemaining() }
            .onReceive(timer) { _ in updateTimeRemaining() }
    }
    
    private func updateTimeRemaining() {
        timeRemaining = CountdownFormatter.timeRemaining(until: expiresAt)
    }
    
    private var colorForTimeRemaining: Color {
        guard timeRemaining > 0 else { return .red }
        if timeRemaining < 60 { return .red }
        if timeRemaining < 300 { return .orange }
        return .secondary
    }
}

#Preview {
    VStack(spacing: 20) {
        CountdownTimerView(expiresAt: Date().addingTimeInterval(3665))
        CountdownTimerView(expiresAt: Date().addingTimeInterval(125))
        CountdownTimerView(expiresAt: Date().addingTimeInterval(45))
        CountdownTimerView(expiresAt: Date().addingTimeInterval(-10))
    }
    .padding()
}
