//
//  LocationModels.swift
//  Inviso
//
//  Models for location sharing in chat.
//

import Foundation
import CoreLocation

/// Location data compatible with Android format
struct LocationData: Codable, Equatable {
    let type: String = "location"
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
    let timestamp: Int64 // Unix timestamp in milliseconds
    
    init(latitude: Double, longitude: Double, accuracy: Double? = nil, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.timestamp = Int64(timestamp.timeIntervalSince1970 * 1000)
    }
    
    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.accuracy = location.horizontalAccuracy
        self.timestamp = Int64(location.timestamp.timeIntervalSince1970 * 1000)
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
    }
    
    /// Convert to JSON string for P2P transmission
    func toJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
    
    /// Parse from JSON string received via P2P
    static func fromJSONString(_ json: String) -> LocationData? {
        guard let data = json.data(using: .utf8),
              let location = try? JSONDecoder().decode(LocationData.self, from: data) else {
            return nil
        }
        return location
    }
}

/// Extended message type to support location
enum MessageContent: Equatable {
    case text(String)
    case location(LocationData)
    
    var isLocation: Bool {
        if case .location = self { return true }
        return false
    }
    
    var locationData: LocationData? {
        if case .location(let data) = self { return data }
        return nil
    }
    
    var textContent: String? {
        if case .text(let text) = self { return text }
        return nil
    }
}
