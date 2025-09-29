//
//  ColorExtensions.swift
//  Inviso
//
//  Shared color utilities
//

import SwiftUI

extension Color {
    /// Initialize a Color from a hex string (with or without # prefix)
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