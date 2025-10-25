//
//  PermissionManager.swift
//  Inviso
//
//  Centralized permission management for all app features.
//

import Foundation
import Combine
import CoreLocation
import AVFoundation
import UserNotifications
import UIKit

/// Manages all app permissions and tracks their status
@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    // MARK: - Published Properties
    
    @Published var locationStatus: PermissionStatus = .notDetermined
    @Published var microphoneStatus: PermissionStatus = .notDetermined
    @Published var notificationStatus: PermissionStatus = .notDetermined
    @Published var cameraStatus: PermissionStatus = .notDetermined
    
    // MARK: - Permission Status
    
    enum PermissionStatus {
        case notDetermined
        case authorized
        case denied
        case restricted
        
        var isGranted: Bool {
            self == .authorized
        }
        
        var displayText: String {
            switch self {
            case .notDetermined: return "Not Set"
            case .authorized: return "Enabled"
            case .denied: return "Denied"
            case .restricted: return "Restricted"
            }
        }
        
        var displayColor: String {
            switch self {
            case .notDetermined: return "orange"
            case .authorized: return "green"
            case .denied: return "red"
            case .restricted: return "gray"
            }
        }
    }
    
    // MARK: - Feature Availability
    
    var canUseLocationSharing: Bool {
        locationStatus.isGranted
    }
    
    var canUseVoiceMessages: Bool {
        microphoneStatus.isGranted
    }
    
    var canReceiveNotifications: Bool {
        notificationStatus.isGranted
    }
    
    var canScanQRCodes: Bool {
        cameraStatus.isGranted
    }
    
    // MARK: - Initialization
    
    private init() {
        Task {
            await refreshAllPermissions()
        }
    }
    
    // MARK: - Permission Checking
    
    /// Refresh all permission statuses
    func refreshAllPermissions() async {
        await refreshLocationPermission()
        await refreshMicrophonePermission()
        await refreshNotificationPermission()
        await refreshCameraPermission()
    }
    
    /// Check location permission status
    func refreshLocationPermission() async {
        let status = LocationManager.shared.authorizationStatus
        locationStatus = convertLocationStatus(status)
    }
    
    /// Check microphone permission status
    func refreshMicrophonePermission() async {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                microphoneStatus = .authorized
            case .denied:
                microphoneStatus = .denied
            case .undetermined:
                microphoneStatus = .notDetermined
            @unknown default:
                microphoneStatus = .notDetermined
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                microphoneStatus = .authorized
            case .denied:
                microphoneStatus = .denied
            case .undetermined:
                microphoneStatus = .notDetermined
            @unknown default:
                microphoneStatus = .notDetermined
            }
        }
    }
    
    /// Check notification permission status
    func refreshNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .notDetermined:
            notificationStatus = .notDetermined
        case .authorized, .provisional, .ephemeral:
            notificationStatus = .authorized
        case .denied:
            notificationStatus = .denied
        @unknown default:
            notificationStatus = .notDetermined
        }
    }
    
    /// Check camera permission status
    func refreshCameraPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            cameraStatus = .notDetermined
        case .restricted:
            cameraStatus = .restricted
        case .denied:
            cameraStatus = .denied
        case .authorized:
            cameraStatus = .authorized
        @unknown default:
            cameraStatus = .notDetermined
        }
    }
    
    // MARK: - Permission Requests
    
    /// Request location permission
    func requestLocationPermission() async -> Bool {
        LocationManager.shared.requestPermission()
        
        // Wait for the permission dialog and response
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Refresh status multiple times to catch the change
        for _ in 0..<3 {
            await refreshLocationPermission()
            if locationStatus.isGranted {
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        return locationStatus.isGranted
    }
    
    /// Request microphone permission
    func requestMicrophonePermission() async -> Bool {
        let recorder = VoiceRecorder()
        let granted = await recorder.requestPermission()
        await refreshMicrophonePermission()
        return granted
    }
    
    /// Request notification permission
    func requestNotificationPermission() async -> Bool {
        do {
            try await PushNotificationManager.shared.requestAuthorization()
            await refreshNotificationPermission()
            return notificationStatus.isGranted
        } catch {
            await refreshNotificationPermission()
            return false
        }
    }
    
    /// Request camera permission
    func requestCameraPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    await self.refreshCameraPermission()
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    /// Open system settings for the app
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func convertLocationStatus(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorizedAlways, .authorizedWhenInUse:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }
}
