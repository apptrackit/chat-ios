//
//  NotificationSettingsView.swift
//  Inviso
//
//  Settings view for managing push notification preferences.
//

import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @EnvironmentObject var pushManager: PushNotificationManager
    @State private var isRequestingAuthorization = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: notificationIcon)
                        .foregroundColor(notificationColor)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Push Notifications")
                            .font(.headline)
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    statusBadge
                }
                .padding(.vertical, 8)
            } header: {
                Text("Status")
            } footer: {
                Text("Receive notifications when someone joins your chat room while you're away.")
            }
            
            Section {
                if pushManager.authorizationStatus == .notDetermined {
                    Button(action: requestAuthorization) {
                        HStack {
                            Image(systemName: "bell.badge")
                            Text("Enable Notifications")
                            Spacer()
                            if isRequestingAuthorization {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRequestingAuthorization)
                } else if pushManager.authorizationStatus == .denied {
                    Button(action: openSettings) {
                        HStack {
                            Image(systemName: "gear")
                            Text("Open Settings")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if pushManager.authorizationStatus == .authorized {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Notifications Enabled")
                        Spacer()
                    }
                    
                    // Show a manual register button if authorized but no token
                    if pushManager.deviceToken == nil {
                        Button(action: manualRegister) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Register for Push Notifications")
                                Spacer()
                                if isRequestingAuthorization {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRequestingAuthorization)
                    }
                    
                    Button(action: openSettings) {
                        HStack {
                            Image(systemName: "gear")
                            Text("Manage in Settings")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Actions")
            }
            
            if pushManager.deviceToken != nil {
                Section {
                    HStack {
                        Text("Device Token")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(pushManager.deviceToken?.prefix(16) ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                } header: {
                    Text("Debug")
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(
                        icon: "lock.shield",
                        title: "Privacy First",
                        description: "Your device token is only stored temporarily and never leaves our servers."
                    )
                    
                    Divider()
                    
                    InfoRow(
                        icon: "clock",
                        title: "Ephemeral",
                        description: "Tokens are automatically deleted when chat sessions expire."
                    )
                    
                    Divider()
                    
                    InfoRow(
                        icon: "bell.slash",
                        title: "Minimal",
                        description: "Notifications only sent when someone is waiting in your chat room."
                    )
                }
                .padding(.vertical, 8)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Notifications")
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusText: String {
        switch pushManager.authorizationStatus {
        case .notDetermined:
            return "Not configured"
        case .denied:
            return "Disabled in Settings"
        case .authorized:
            return "Enabled"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var notificationIcon: String {
        switch pushManager.authorizationStatus {
        case .notDetermined:
            return "bell.badge.slash"
        case .denied:
            return "bell.slash"
        case .authorized:
            return "bell.badge.fill"
        case .provisional:
            return "bell.badge"
        case .ephemeral:
            return "bell.badge"
        @unknown default:
            return "bell"
        }
    }
    
    private var notificationColor: Color {
        switch pushManager.authorizationStatus {
        case .authorized:
            return .green
        case .denied:
            return .red
        default:
            return .orange
        }
    }
    
    private var statusBadge: some View {
        Group {
            switch pushManager.authorizationStatus {
            case .authorized:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .denied:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            default:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
            }
        }
        .font(.title3)
    }
    
    // MARK: - Actions
    
    private func requestAuthorization() {
        isRequestingAuthorization = true
        
        Task {
            do {
                try await pushManager.requestAuthorization()
            } catch {
                errorMessage = "Failed to request notification authorization: \(error.localizedDescription)"
                showError = true
            }
            
            isRequestingAuthorization = false
        }
    }
    
    @MainActor
    private func manualRegister() {
        isRequestingAuthorization = true
        
        print("[Push] Manual registration triggered from settings")
        UIApplication.shared.registerForRemoteNotifications()
        
        // Give it a moment to register
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            isRequestingAuthorization = false
        }
    }
    
    private func openSettings() {
        pushManager.openNotificationSettings()
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NotificationSettingsView()
                .environmentObject(PushNotificationManager.shared)
        }
    }
}
