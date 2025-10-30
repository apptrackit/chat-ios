//
//  MessageExpirationView.swift
//  Inviso
//
//  Shows expiration countdown on message bubbles
//
//  Created by GitHub Copilot on 10/26/25.
//

import SwiftUI

struct MessageExpirationView: View {
    let expiresAt: Date
    @State private var timeRemaining: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        if timeRemaining > 0 {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.caption2)
                
                Text(timeRemainingString)
                    .font(.caption2)
                    .monospacedDigit()
            }
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .cornerRadius(6)
            .onAppear {
                updateTimeRemaining()
                startTimer()
            }
            .onDisappear {
                stopTimer()
            }
        }
    }
    
    private var color: Color {
        if timeRemaining < 300 { // < 5 minutes
            return .red
        } else if timeRemaining < 3600 { // < 1 hour
            return .orange
        } else {
            return .secondary
        }
    }
    
    private var timeRemainingString: String {
        let seconds = Int(timeRemaining)
        
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h"
        } else {
            let days = seconds / 86400
            return "\(days)d"
        }
    }
    
    private func updateTimeRemaining() {
        timeRemaining = max(0, expiresAt.timeIntervalSinceNow)
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateTimeRemaining()
            if timeRemaining <= 0 {
                stopTimer()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// More detailed view for long press or info
struct DetailedExpirationView: View {
    let expiresAt: Date
    let lifetime: MessageLifetime?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.badge.xmark")
                    .foregroundColor(.orange)
                Text("Message Expiration")
                    .font(.headline)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Expires:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(expiresAt, style: .relative)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Exact time:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(expiresAt, format: .dateTime)
                        .font(.caption)
                }
                
                if let lifetime = lifetime {
                    HStack {
                        Text("Policy:")
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: lifetime.icon)
                            Text(lifetime.displayName)
                        }
                        .font(.caption)
                    }
                }
            }
            
            if expiresAt.timeIntervalSinceNow < 300 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("This message will be deleted soon")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview("Expiration Badge") {
    VStack(spacing: 20) {
        MessageExpirationView(expiresAt: Date().addingTimeInterval(30)) // 30 seconds
        MessageExpirationView(expiresAt: Date().addingTimeInterval(300)) // 5 minutes
        MessageExpirationView(expiresAt: Date().addingTimeInterval(3600)) // 1 hour
        MessageExpirationView(expiresAt: Date().addingTimeInterval(86400)) // 1 day
    }
    .padding()
}

#Preview("Detailed View") {
    DetailedExpirationView(
        expiresAt: Date().addingTimeInterval(3600),
        lifetime: .oneHour
    )
    .padding()
}
