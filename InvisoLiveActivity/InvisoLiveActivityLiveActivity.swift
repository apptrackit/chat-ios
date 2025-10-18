//
//  InvisoLiveActivityLiveActivity.swift
//  InvisoLiveActivity
//
//  Created by Bence Szilagyi on 10/18/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Waiting Status
enum WaitingStatus: String, Codable, Hashable {
    case waiting = "waiting"
    case connected = "connected"
}

// MARK: - Live Activity Attributes
struct InvisoLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var roomName: String
        var status: WaitingStatus
        var startTime: Date
    }

    // Fixed property - the room we're waiting for
    var roomId: String
}

struct InvisoLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: InvisoLiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            LiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI - shown when user long-presses the Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    statusIcon(for: context.state.status)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsedTime(since: context.state.startTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Text(statusText(for: context.state.status))
                            .font(.headline)
                        Text("in \(context.state.roomName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } compactLeading: {
                statusIcon(for: context.state.status)
            } compactTrailing: {
                // Show compact status indicator
                Circle()
                    .fill(statusColor(for: context.state.status))
                    .frame(width: 8, height: 8)
            } minimal: {
                // Minimal view - just the status icon
                statusIcon(for: context.state.status)
            }
            .widgetURL(URL(string: "inviso://open"))
            .keylineTint(statusColor(for: context.state.status))
        }
    }
    
    // MARK: - Status Helpers
    
    @ViewBuilder
    private func statusIcon(for status: WaitingStatus) -> some View {
        switch status {
        case .waiting:
            Image(systemName: "hourglass")
                .foregroundColor(.orange)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }
    
    private func statusColor(for status: WaitingStatus) -> Color {
        switch status {
        case .waiting:
            return .orange
        case .connected:
            return .green
        }
    }
    
    private func statusText(for status: WaitingStatus) -> String {
        switch status {
        case .waiting:
            return "Waiting for other client"
        case .connected:
            return "Other client joined!"
        }
    }
    
    @ViewBuilder
    private func elapsedTime(since startTime: Date) -> some View {
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        Text(String(format: "%d:%02d", minutes, seconds))
    }
}

// MARK: - Lock Screen / Banner View
struct LiveActivityView: View {
    let context: ActivityViewContext<InvisoLiveActivityAttributes>
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            statusIcon
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                // Status Text
                Text(statusText)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Room Name
                Text("in \(context.state.roomName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Elapsed Time
                Text("Waiting for \(elapsedTimeText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .activityBackgroundTint(backgroundColor)
        .activitySystemActionForegroundColor(.white)
    }
    
    // MARK: - View Properties
    
    private var statusIcon: some View {
        Group {
            switch context.state.status {
            case .waiting:
                Image(systemName: "hourglass")
                    .foregroundColor(.orange)
            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
    
    private var statusText: String {
        switch context.state.status {
        case .waiting:
            return "Waiting for other client"
        case .connected:
            return "Other client joined!"
        }
    }
    
    private var backgroundColor: Color {
        switch context.state.status {
        case .waiting:
            return Color.orange.opacity(0.1)
        case .connected:
            return Color.green.opacity(0.1)
        }
    }
    
    private var elapsedTimeText: String {
        let elapsed = Date().timeIntervalSince(context.state.startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        
        if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}

// MARK: - Preview
extension InvisoLiveActivityAttributes {
    fileprivate static var preview: InvisoLiveActivityAttributes {
        InvisoLiveActivityAttributes(roomId: "preview-room-123")
    }
}

extension InvisoLiveActivityAttributes.ContentState {
    fileprivate static var waiting: InvisoLiveActivityAttributes.ContentState {
        InvisoLiveActivityAttributes.ContentState(
            roomName: "Room A",
            status: .waiting,
            startTime: Date().addingTimeInterval(-120) // 2 minutes ago
        )
    }
     
    fileprivate static var connected: InvisoLiveActivityAttributes.ContentState {
        InvisoLiveActivityAttributes.ContentState(
            roomName: "Room A",
            status: .connected,
            startTime: Date().addingTimeInterval(-150) // 2.5 minutes ago
        )
    }
}

#Preview("Notification", as: .content, using: InvisoLiveActivityAttributes.preview) {
   InvisoLiveActivityLiveActivity()
} contentStates: {
    InvisoLiveActivityAttributes.ContentState.waiting
    InvisoLiveActivityAttributes.ContentState.connected
}
