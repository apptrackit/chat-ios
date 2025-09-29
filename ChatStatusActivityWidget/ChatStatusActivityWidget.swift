//
//  ChatStatusActivityWidget.swift
//  ChatStatusActivityWidget
//
//  Live Activity Widget for Chat Status
//

import ActivityKit
import WidgetKit
import SwiftUI

@main
struct ChatStatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        ChatStatusActivityWidget()
    }
}

@available(iOS 16.1, *)
struct ChatStatusActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChatStatusAttributes.self) { context in
            // Lock Screen view
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view regions
                DynamicIslandExpandedRegion(.leading) {
                    StatusDot(colorHex: context.state.colorHex, size: 20)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.title)
                            .font(.headline)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                        Text("Room: \(context.attributes.roomId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(spacing: 4) {
                        Image(systemName: context.state.phase == .connected ? "checkmark.circle.fill" : "clock.circle")
                            .font(.title2)
                            .foregroundColor(Color(hex: context.state.colorHex))
                        Text(context.state.phase == .connected ? "Connected" : "Waiting")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                }
            } compactLeading: {
                StatusDot(colorHex: context.state.colorHex, size: 16)
            } compactTrailing: {
                Image(systemName: context.state.phase == .connected ? "checkmark" : "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: context.state.colorHex))
            } minimal: {
                StatusDot(colorHex: context.state.colorHex, size: 12)
            }
        }
    }
}

// MARK: - Lock Screen View

@available(iOS 16.1, *)
struct LockScreenView: View {
    let context: ActivityViewContext<ChatStatusAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatusDot(colorHex: context.state.colorHex, size: 24)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("Room: \(context.attributes.roomId)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Image(systemName: context.state.phase == .connected ? "person.2.fill" : "person.crop.circle.badge.clock")
                        .font(.title2)
                        .foregroundColor(Color(hex: context.state.colorHex))
                    
                    Text(context.state.phase == .connected ? "Connected" : "Waiting")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Color(hex: context.state.colorHex))
                }
            }
            
            // Progress indicator for waiting state
            if context.state.phase == .waiting {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color(hex: context.state.colorHex).opacity(0.3))
                            .frame(width: 6, height: 6)
                            .scaleEffect(1.0)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                value: context.state.lastUpdated
                            )
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("\(context.state.title) in room \(context.attributes.roomId)")
    }
}

// MARK: - Supporting Views

@available(iOS 16.1, *)
struct StatusDot: View {
    let colorHex: String
    let size: CGFloat
    
    var body: some View {
        Circle()
            .fill(Color(hex: colorHex))
            .frame(width: size, height: size)
            .shadow(color: Color(hex: colorHex).opacity(0.3), radius: 2, x: 0, y: 1)
            .overlay(
                Circle()
                    .stroke(Color(hex: colorHex).opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        var hex = hex
        if hex.hasPrefix("#") { 
            hex.removeFirst() 
        }
        
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let r = Double((int >> 16) & 0xff) / 255
        let g = Double((int >> 8) & 0xff) / 255
        let b = Double(int & 0xff) / 255
        
        self = Color(red: r, green: g, blue: b)
    }
}