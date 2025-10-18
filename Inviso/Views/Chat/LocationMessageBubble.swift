//
//  LocationMessageBubble.swift
//  Inviso
//
//  Beautiful map preview for location messages in chat.
//

import SwiftUI
import MapKit

struct LocationMessageBubble: View {
    let location: LocationData
    let isFromSelf: Bool
    let showTime: Bool
    let timestamp: Date
    
    @State private var region: MKCoordinateRegion
    @State private var showFullMap = false
    
    init(location: LocationData, isFromSelf: Bool, showTime: Bool, timestamp: Date) {
        self.location = location
        self.isFromSelf = isFromSelf
        self.showTime = showTime
        self.timestamp = timestamp
        
        // Initialize region
        _region = State(initialValue: MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }
    
    var body: some View {
        VStack(alignment: isFromSelf ? .trailing : .leading, spacing: 4) {
            // Time indicator (optional)
            if showTime {
                Text(timestamp.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            
            // Location bubble
            VStack(spacing: 0) {
                // Map snapshot
                Map(position: .constant(.region(region)), interactionModes: []) {
                    Annotation("", coordinate: location.coordinate) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red, .white)
                            .shadow(radius: 2)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                // Location info footer
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location")
                            .font(.caption.weight(.semibold))
                        Text(coordinateText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Open in Maps button
                    Button {
                        openInMaps()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.circle.fill")
                                .font(.caption)
                            Text("Open")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(.blue.opacity(0.15))
                        }
                    }
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                }
            }
            .frame(maxWidth: 280)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isFromSelf ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isFromSelf ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .contextMenu {
                Button {
                    openInMaps()
                } label: {
                    Label("Open in Maps", systemImage: "map")
                }
                
                Button {
                    copyCoordinates()
                } label: {
                    Label("Copy Coordinates", systemImage: "doc.on.doc")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isFromSelf ? .trailing : .leading)
        .padding(.horizontal, 12)
    }
    
    private var coordinateText: String {
        String(format: "%.4f, %.4f", location.latitude, location.longitude)
    }
    
    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: location.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Shared Location"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: location.coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        ])
    }
    
    private func copyCoordinates() {
        UIPasteboard.general.string = coordinateText
    }
}

#Preview {
    VStack(spacing: 20) {
        LocationMessageBubble(
            location: LocationData(latitude: 37.7749, longitude: -122.4194),
            isFromSelf: false,
            showTime: true,
            timestamp: Date()
        )
        
        LocationMessageBubble(
            location: LocationData(latitude: 40.7128, longitude: -74.0060),
            isFromSelf: true,
            showTime: false,
            timestamp: Date()
        )
    }
    .padding()
}
