//
//  PermissionsView.swift
//  Inviso
//
//  View to manage and review app permissions in settings.
//

import SwiftUI

struct PermissionsView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var isRequestingPermission = false
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Permissions allow you to use specific features. If a permission is disabled, the related feature won't be available.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("App Permissions")) {
                PermissionRow(
                    icon: "location.fill",
                    iconColor: .blue,
                    title: "Location",
                    description: "Share your location in chats",
                    status: permissionManager.locationStatus,
                    feature: "Location Sharing",
                    isEnabled: permissionManager.canUseLocationSharing,
                    isRequesting: isRequestingPermission,
                    onRequest: requestLocationPermission,
                    onOpenSettings: permissionManager.openSettings
                )
                
                PermissionRow(
                    icon: "mic.fill",
                    iconColor: .red,
                    title: "Microphone",
                    description: "Record and send voice messages",
                    status: permissionManager.microphoneStatus,
                    feature: "Voice Messages",
                    isEnabled: permissionManager.canUseVoiceMessages,
                    isRequesting: isRequestingPermission,
                    onRequest: requestMicrophonePermission,
                    onOpenSettings: permissionManager.openSettings
                )
                
                PermissionRow(
                    icon: "bell.fill",
                    iconColor: .orange,
                    title: "Notifications",
                    description: "Get notified when someone joins your room",
                    status: permissionManager.notificationStatus,
                    feature: "Push Notifications",
                    isEnabled: permissionManager.canReceiveNotifications,
                    isRequesting: isRequestingPermission,
                    onRequest: requestNotificationPermission,
                    onOpenSettings: permissionManager.openSettings
                )
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("About Permissions")
                            .font(.headline)
                    }
                    
                    Text("Permissions are handled by iOS. If you've previously denied a permission, you'll need to enable it in the Settings app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
            
            Section {
                NavigationLink {
                    FeatureAvailabilityView()
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.clipboard")
                        Text("View Feature Availability")
                        Spacer()
                    }
                }
                
                Button {
                    Task {
                        await permissionManager.refreshAllPermissions()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Permission Status")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await permissionManager.refreshAllPermissions()
        }
    }
    
    // MARK: - Permission Requests
    
    private func requestLocationPermission() {
        guard permissionManager.locationStatus == .notDetermined else { return }
        isRequestingPermission = true
        Task {
            _ = await permissionManager.requestLocationPermission()
            isRequestingPermission = false
        }
    }
    
    private func requestMicrophonePermission() {
        guard permissionManager.microphoneStatus == .notDetermined else { return }
        isRequestingPermission = true
        Task {
            _ = await permissionManager.requestMicrophonePermission()
            isRequestingPermission = false
        }
    }
    
    private func requestNotificationPermission() {
        guard permissionManager.notificationStatus == .notDetermined else { return }
        isRequestingPermission = true
        Task {
            _ = await permissionManager.requestNotificationPermission()
            isRequestingPermission = false
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let status: PermissionManager.PermissionStatus
    let feature: String
    let isEnabled: Bool
    let isRequesting: Bool
    let onRequest: () -> Void
    let onOpenSettings: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                statusBadge
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Feature Status")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(feature)
                    }
                    .font(.caption)
                    .foregroundColor(isEnabled ? .green : .red)
                }
                
                Spacer()
                
                actionButton
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption)
            Text(status.displayText)
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.15))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var actionButton: some View {
        if status == .denied {
            Button {
                onOpenSettings()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(8)
            }
        } else if status == .notDetermined {
            Button {
                onRequest()
            } label: {
                HStack(spacing: 4) {
                    if isRequesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Enable")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .disabled(isRequesting)
        }
    }
    
    private var statusIcon: String {
        switch status {
        case .notDetermined: return "questionmark.circle"
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .restricted: return "exclamationmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .notDetermined: return .orange
        case .authorized: return .green
        case .denied: return .red
        case .restricted: return .gray
        }
    }
}

#Preview {
    NavigationStack {
        PermissionsView()
    }
}
