//
//  CountdownFormatter.swift
//  Inviso
//
//  Utility for formatting countdown timers for session expiry.
//

import Foundation

struct CountdownFormatter {
    /// Formats remaining time interval with smart precision:
    /// - Hours remaining: "1h 23m 45s"
    /// - Minutes remaining: "23m 45s"
    /// - Seconds only: "45s"
    /// - Expired: "Expired"
    static func format(timeRemaining: TimeInterval) -> String {
        guard timeRemaining > 0 else { return "Expired" }
        
        let totalSeconds = Int(timeRemaining)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    /// Calculates time remaining from expiry date
    static func timeRemaining(until expiryDate: Date?) -> TimeInterval {
        guard let expiry = expiryDate else { return 0 }
        return expiry.timeIntervalSince(Date())
    }
}
