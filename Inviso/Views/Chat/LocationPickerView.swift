//
//  LocationPickerView.swift
//  Inviso
//
//  Modern location picker with current location and custom pin options.
//

import SwiftUI
import MapKit
import CoreLocation

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = LocationManager.shared
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var isLoadingCurrentLocation = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var pinPlacementMode = false // Manual pin placement mode
    
    let onLocationSelected: (LocationData) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Map with optional pin
                ZStack {
                    Map(position: $cameraPosition, interactionModes: .all) {
                        if let coordinate = selectedCoordinate, !pinPlacementMode {
                            Annotation("", coordinate: coordinate) {
                                LocationPin()
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .gesture(
                        // Tap gesture to place pin manually
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                if pinPlacementMode {
                                    // User tapped to place pin - we need to convert screen coordinates to map coordinates
                                    // This is a limitation - we'll use center coordinate when tapping
                                    // Better UX: User drags map to desired location, then pin appears at center
                                }
                            }
                    )
                    
                    // Center crosshair when in pin placement mode
                    if pinPlacementMode {
                        VStack(spacing: 0) {
                            LocationPin()
                                .scaleEffect(1.2)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .onMapCameraChange { context in
                    // If in pin placement mode, continuously update coordinate to center
                    if pinPlacementMode {
                        selectedCoordinate = context.camera.centerCoordinate
                    }
                }
                
                // Floating controls card
                VStack(spacing: 0) {
                    // Action buttons
                    HStack(spacing: 12) {
                        if !pinPlacementMode {
                            // Current Location Button
                            Button {
                                Task {
                                    await loadCurrentLocation()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if isLoadingCurrentLocation {
                                        ProgressView()
                                            .tint(.primary)
                                    } else {
                                        Image(systemName: "location.fill")
                                            .font(.body.weight(.semibold))
                                    }
                                    Text("Current")
                                        .font(.body.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.glass)
                            .disabled(isLoadingCurrentLocation)
                            
                            // Place Pin Button
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    pinPlacementMode = true
                                    // Set initial coordinate to map center if none selected
                                    if selectedCoordinate == nil {
                                        // Will be updated by onMapCameraChange
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "mappin")
                                        .font(.body.weight(.semibold))
                                    Text("Pin")
                                        .font(.body.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.glass)
                        } else {
                            // Cancel Pin Placement
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    pinPlacementMode = false
                                    selectedCoordinate = nil
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "xmark")
                                        .font(.body.weight(.semibold))
                                    Text("Cancel")
                                        .font(.body.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.glass)
                            
                            // Confirm Pin Placement
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    pinPlacementMode = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                    Text("Confirm")
                                        .font(.body.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.glass)
                            .disabled(selectedCoordinate == nil)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    
                    // Send Button (only shown when location is selected and not in placement mode)
                    if selectedCoordinate != nil && !pinPlacementMode {
                        Button {
                            sendLocation()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "paperplane.fill")
                                    .font(.body.weight(.semibold))
                                Text("Send Location")
                                    .font(.body.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.glass)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    Spacer()
                        .frame(height: 24)
                }
                .padding(.bottom, 8)
            }
            .navigationTitle("Share Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Location Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
                if locationManager.authorizationStatus == .denied {
                    Button("Open Settings") {
                        locationManager.openSettings()
                    }
                }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                // Default to a reasonable starting position if no location yet
                if selectedCoordinate == nil {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco default
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                }
            }
        }
    }
    
    private func loadCurrentLocation() async {
        isLoadingCurrentLocation = true
        defer { isLoadingCurrentLocation = false }
        
        do {
            let location = try await locationManager.getCurrentLocation()
            selectedCoordinate = location.coordinate
            pinPlacementMode = false // Exit pin placement mode if active
            
            // Animate to current location
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        } catch {
            if let locationError = error as? LocationManager.LocationError {
                errorMessage = locationError.localizedDescription
            } else {
                errorMessage = "Unable to get your current location. Please try again."
            }
            showError = true
        }
    }
    
    private func sendLocation() {
        guard let coordinate = selectedCoordinate else { return }
        
        let locationData = LocationData(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            accuracy: nil, // We don't have accuracy for manually placed pins
            timestamp: Date()
        )
        
        onLocationSelected(locationData)
        dismiss()
    }
}

/// Custom location pin view
struct LocationPin: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red, .white)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6).repeatForever(autoreverses: true), value: isAnimating)
            
            // Pin shadow
            Ellipse()
                .fill(.black.opacity(0.2))
                .frame(width: 20, height: 6)
                .blur(radius: 2)
                .offset(y: -3)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    LocationPickerView { location in
        print("Selected location: \(location.latitude), \(location.longitude)")
    }
}
