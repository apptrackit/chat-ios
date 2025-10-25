//
//  FeatureAvailabilityView.swift
//  Inviso
//
//  Shows which features are available based on current permissions.
//  This can be shown in settings or after permissions are set.
//

import SwiftUI

struct FeatureAvailabilityView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Based on your current permissions, here's what you can do in Inviso:")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("Available Features")) {
                FeatureStatusRow(
                    icon: "message.fill",
                    title: "Text Messaging",
                    description: "Send and receive encrypted text messages",
                    isAvailable: true,
                    requiresPermission: nil
                )
                
                FeatureStatusRow(
                    icon: "waveform",
                    title: "Voice Messages",
                    description: "Record and send voice messages",
                    isAvailable: permissionManager.canUseVoiceMessages,
                    requiresPermission: "Microphone"
                )
                
                FeatureStatusRow(
                    icon: "location.fill",
                    title: "Location Sharing",
                    description: "Share your current location in chats",
                    isAvailable: permissionManager.canUseLocationSharing,
                    requiresPermission: "Location"
                )
                
                FeatureStatusRow(
                    icon: "bell.fill",
                    title: "Push Notifications",
                    description: "Get notified when someone joins your room",
                    isAvailable: permissionManager.canReceiveNotifications,
                    requiresPermission: "Notifications"
                )
            }
            
            Section(header: Text("Always Available")) {
                FeatureStatusRow(
                    icon: "lock.shield.fill",
                    title: "End-to-End Encryption",
                    description: "All messages are encrypted by default",
                    isAvailable: true,
                    requiresPermission: nil
                )
                
                FeatureStatusRow(
                    icon: "network",
                    title: "Peer-to-Peer Connection",
                    description: "Direct connection between devices",
                    isAvailable: true,
                    requiresPermission: nil
                )
                
                FeatureStatusRow(
                    icon: "eye.slash.fill",
                    title: "No Message History",
                    description: "Messages are never stored permanently",
                    isAvailable: true,
                    requiresPermission: nil
                )
                
                FeatureStatusRow(
                    icon: "timer",
                    title: "Ephemeral Sessions",
                    description: "All sessions expire after 24 hours",
                    isAvailable: true,
                    requiresPermission: nil
                )
            }
        }
        .navigationTitle("Features")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await permissionManager.refreshAllPermissions()
        }
    }
}

private struct FeatureStatusRow: View {
    let icon: String
    let title: String
    let description: String
    let isAvailable: Bool
    let requiresPermission: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let permission = requiresPermission {
                    HStack(spacing: 4) {
                        Image(systemName: statusIcon)
                            .font(.caption2)
                        Text(isAvailable ? "Enabled" : "Requires \(permission)")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(6)
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("Always Available")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
                    .padding(.top, 4)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var iconColor: Color {
        if requiresPermission == nil {
            return .blue
        }
        return isAvailable ? .blue : .gray
    }
    
    private var statusIcon: String {
        isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    
    private var statusColor: Color {
        isAvailable ? .green : .orange
    }
}

#Preview {
    NavigationStack {
        FeatureAvailabilityView()
    }
}
