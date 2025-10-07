//
//  SessionAboutView.swift
//  Inviso
//
//  Displays detailed information about a session in a clean, minimal popup.
//

import SwiftUI
import Combine

struct SessionAboutView: View {
    let session: ChatSession
    
    @State private var timeRemaining: TimeInterval = 0
    @State private var timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: iconForStatus)
                        .font(.system(size: 48))
                        .foregroundColor(colorForStatus)
                    
                    Text(session.displayName)
                        .font(.title2.weight(.bold))
                    
                    statusBadge
                }
                .padding(.top, 20)
                
                // Information Cards - Status Specific
                VStack(spacing: 16) {
                    switch session.status {
                    case .accepted:
                        activeSessionInfo
                    case .pending:
                        pendingSessionInfo
                    case .expired:
                        expiredSessionInfo
                    case .closed:
                        closedSessionInfo
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemGroupedBackground))
        .onAppear { updateTimeRemaining() }
        .onReceive(timer) { _ in updateTimeRemaining() }
    }
    
    // MARK: - Status-Specific Views
    
    @ViewBuilder
    private var activeSessionInfo: some View {
        infoCard(title: "Join Code", value: "\(session.code) (Used)", systemImage: "checkmark.circle")
        
        if let roomId = session.roomId {
            infoCard(title: "Room ID", value: roomId, systemImage: "key", monospaced: true)
        }
        
        infoCard(title: "Created", value: formatDate(session.createdAt), systemImage: "calendar")
        
        if let firstConnected = session.firstConnectedAt {
            infoCard(title: "First Connected", value: formatDate(firstConnected), systemImage: "link")
        }
        
        infoCard(
            title: "Last Activity",
            value: formatRelativeDate(session.lastActivityDate),
            systemImage: "clock.arrow.circlepath"
        )
        
        infoCard(
            title: "Role",
            value: session.isCreatedByMe ? "Creator" : "Joiner",
            systemImage: session.isCreatedByMe ? "person.badge.plus" : "person.badge.key"
        )
        
        infoCard(
            title: "Device ID",
            value: String(session.ephemeralDeviceId.prefix(12)) + "...",
            systemImage: "iphone",
            monospaced: true
        )
    }
    
    @ViewBuilder
    private var pendingSessionInfo: some View {
        infoCard(title: "Join Code", value: session.code, systemImage: "number")
        
        infoCard(title: "Created", value: formatDate(session.createdAt), systemImage: "calendar")
        
        if let expires = session.expiresAt {
            infoCard(
                title: "Expires",
                value: formatDate(expires),
                systemImage: "clock",
                valueColor: timeRemainingColor(expires)
            )
            
            if timeRemaining > 0 {
                infoCard(
                    title: "Time Remaining",
                    value: CountdownFormatter.format(timeRemaining: timeRemaining),
                    systemImage: "hourglass",
                    valueColor: timeRemainingColor(expires)
                )
            }
        }
        
        infoCard(
            title: "Role",
            value: session.isCreatedByMe ? "Creator" : "Joiner",
            systemImage: session.isCreatedByMe ? "person.badge.plus" : "person.badge.key"
        )
        
        infoCard(
            title: "Device ID",
            value: String(session.ephemeralDeviceId.prefix(12)) + "...",
            systemImage: "iphone",
            monospaced: true
        )
    }
    
    @ViewBuilder
    private var expiredSessionInfo: some View {
        infoCard(title: "Join Code", value: session.code, systemImage: "number")
        
        infoCard(title: "Created", value: formatDate(session.createdAt), systemImage: "calendar")
        
        if let expires = session.expiresAt {
            infoCard(
                title: "Expired",
                value: formatDate(expires),
                systemImage: "clock.badge.xmark",
                valueColor: .red
            )
        }
        
        infoCard(
            title: "Role",
            value: session.isCreatedByMe ? "Creator" : "Joiner",
            systemImage: session.isCreatedByMe ? "person.badge.plus" : "person.badge.key"
        )
        
        infoCard(
            title: "Device ID",
            value: String(session.ephemeralDeviceId.prefix(12)) + "...",
            systemImage: "iphone",
            monospaced: true
        )
    }
    
    @ViewBuilder
    private var closedSessionInfo: some View {
        infoCard(title: "Join Code", value: "\(session.code) (Used)", systemImage: "checkmark.circle")
        
        infoCard(title: "Created", value: formatDate(session.createdAt), systemImage: "calendar")
        
        if let closedDate = session.closedAt {
            infoCard(
                title: "Closed",
                value: formatDate(closedDate),
                systemImage: "xmark.circle"
            )
        }
        
        infoCard(
            title: "Last Activity",
            value: formatRelativeDate(session.lastActivityDate),
            systemImage: "clock.arrow.circlepath"
        )
        
        infoCard(
            title: "Role",
            value: session.isCreatedByMe ? "Creator" : "Joiner",
            systemImage: session.isCreatedByMe ? "person.badge.plus" : "person.badge.key"
        )
        
        infoCard(
            title: "Device ID",
            value: String(session.ephemeralDeviceId.prefix(12)) + "...",
            systemImage: "iphone",
            monospaced: true
        )
    }
    
    // MARK: - Subviews
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colorForStatus)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(colorForStatus.opacity(0.15))
        )
    }
    
    @ViewBuilder
    private func infoCard(title: String, value: String, systemImage: String, monospaced: Bool = false, valueColor: Color? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(monospaced ? .body.monospaced() : .body)
                    .foregroundColor(valueColor ?? .primary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1))
        )
    }
    
    // MARK: - Helpers
    
    private var iconForStatus: String {
        switch session.status {
        case .pending: return "hourglass"
        case .accepted: return "checkmark.circle"
        case .closed: return "xmark.circle"
        case .expired: return "clock.badge.xmark"
        }
    }
    
    private var colorForStatus: Color {
        switch session.status {
        case .pending: return .yellow
        case .accepted: return .green
        case .closed: return .gray
        case .expired: return .orange
        }
    }
    
    private var statusText: String {
        switch session.status {
        case .pending: return "Waiting"
        case .accepted: return "Active"
        case .closed: return "Closed"
        case .expired: return "Expired"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func updateTimeRemaining() {
        timeRemaining = CountdownFormatter.timeRemaining(until: session.expiresAt)
    }
    
    private func timeRemainingColor(_ expiryDate: Date) -> Color {
        let remaining = CountdownFormatter.timeRemaining(until: expiryDate)
        if remaining <= 0 { return .red }
        if remaining < 60 { return .red }
        if remaining < 300 { return .orange }
        return .primary
    }
}

#Preview {
    NavigationView {
        SessionAboutView(session: ChatSession(
            name: "Test Room",
            code: "123456",
            roomId: "abc123xyz789",
            createdAt: Date().addingTimeInterval(-3600),
            expiresAt: Date().addingTimeInterval(1800),
            lastActivityDate: Date().addingTimeInterval(-300),
            status: .accepted,
            isCreatedByMe: true
        ))
    }
}
