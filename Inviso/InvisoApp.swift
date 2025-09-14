//
//  InvisoApp.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/12/25.
//

import SwiftUI

@main
struct InvisoApp: App {
    @StateObject private var chat = ChatManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chat)
        }
    }
}
