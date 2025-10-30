//
//  LocationManager.swift
//  Inviso
//
//  Manages location services and permissions for location sharing.
//

import Foundation
import CoreLocation
import Combine
import UIKit

@MainActor
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    // Published properties
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var locationError: LocationError?
    
    // Internal properties
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    
    enum LocationError: LocalizedError {
        case denied
        case restricted
        case unavailable
        case timeout
        
        var errorDescription: String? {
            switch self {
            case .denied:
                return "Location access denied. Please enable location services in Settings."
            case .restricted:
                return "Location access is restricted on this device."
            case .unavailable:
                return "Unable to determine your location. Please try again."
            case .timeout:
                return "Location request timed out. Please try again."
            }
        }
    }
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }
    
    /// Request location permission
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    /// Get current location (one-time)
    func getCurrentLocation() async throws -> CLLocation {
        // Check authorization
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            if authorizationStatus == .denied {
                throw LocationError.denied
            } else if authorizationStatus == .restricted {
                throw LocationError.restricted
            } else {
                // Request permission
                requestPermission()
                throw LocationError.denied
            }
        }
        
        // Request location
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestLocation()
            
            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if self.locationContinuation != nil {
                    self.locationContinuation = nil
                    continuation.resume(throwing: LocationError.timeout)
                }
            }
        }
    }
    
    /// Check if location services are available
    var isLocationAvailable: Bool {
        CLLocationManager.locationServicesEnabled() &&
        (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways)
    }
    
    /// Open Settings app
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            currentLocation = location
            
            if let continuation = locationContinuation {
                locationContinuation = nil
                continuation.resume(returning: location)
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    locationError = .denied
                case .locationUnknown:
                    locationError = .unavailable
                default:
                    locationError = .unavailable
                }
            }
            
            if let continuation = locationContinuation {
                locationContinuation = nil
                continuation.resume(throwing: LocationError.unavailable)
            }
        }
    }
}
