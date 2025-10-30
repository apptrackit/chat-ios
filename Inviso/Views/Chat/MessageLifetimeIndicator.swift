//
//  MessageLifetimeIndicator.swift
//  Inviso
//
//  Shows current auto-delete policy in ChatView
//
//  Created by GitHub Copilot on 10/26/25.
//

import SwiftUI

struct MessageLifetimeIndicator: View {
    let lifetime: MessageLifetime
    let agreedByBoth: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption2)
                
                Text(lifetime.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if !agreedByBoth {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                agreedByBoth 
                    ? Color.green.opacity(0.15)
                    : Color.orange.opacity(0.15)
            )
            .foregroundColor(
                agreedByBoth 
                    ? .green
                    : .orange
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// Compact version for navigation bar
struct CompactLifetimeIndicator: View {
    let lifetime: MessageLifetime
    let agreedByBoth: Bool
    var onTap: (() -> Void)? = nil
    
    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: lifetime.icon)
                    .font(.caption2)
                
                Text(shortLabel)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isAgreed
                    ? Color.green.opacity(0.15)
                    : Color.orange.opacity(0.15)
            )
            .foregroundColor(
                isAgreed
                    ? .green
                    : .orange
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    // Ephemeral (RAM) is the default, so it's always "agreed" even if not explicitly confirmed
    private var isAgreed: Bool {
        agreedByBoth || lifetime == .ephemeral
    }
    
    private var shortLabel: String {
        switch lifetime {
        case .ephemeral: return "RAM"
        case .oneHour: return "1h"
        case .sixHours: return "6h"
        case .oneDay: return "1d"
        case .sevenDays: return "7d"
        case .thirtyDays: return "30d"
        }
    }
}

#Preview("Full Indicator") {
    VStack(spacing: 20) {
        MessageLifetimeIndicator(
            lifetime: .oneDay,
            agreedByBoth: true,
            onTap: { print("Tapped") }
        )
        
        MessageLifetimeIndicator(
            lifetime: .sevenDays,
            agreedByBoth: false,
            onTap: { print("Tapped") }
        )
        
        MessageLifetimeIndicator(
            lifetime: .ephemeral,
            agreedByBoth: true,
            onTap: { print("Tapped") }
        )
    }
    .padding()
}

#Preview("Compact Indicator") {
    VStack(spacing: 20) {
        CompactLifetimeIndicator(lifetime: .oneDay, agreedByBoth: true)
        CompactLifetimeIndicator(lifetime: .sevenDays, agreedByBoth: false)
        CompactLifetimeIndicator(lifetime: .ephemeral, agreedByBoth: true)
    }
    .padding()
}
