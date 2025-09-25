//
//  ContentView.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/12/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        if #available(iOS 18.0, *) {
            TabView {
                Tab("Sessions", systemImage: "list.bullet.rectangle") {
                    NavigationStack { SessionsView() }
                }
                Tab("Manual Room", systemImage: "rectangle.and.pencil.and.ellipsis") {
                    NavigationStack { ManualRoomView() }
                }
                Tab("LLM", systemImage: "brain.head.profile") {
                    NavigationStack { LLMView() }
                }
            }
        } else {
            // Fallback for older iOS: standard TabView with a dedicated Search tab
            TabView {
                NavigationView { SessionsView() }
                    .tabItem { Label("Sessions", systemImage: "list.bullet.rectangle") }

                NavigationView { ManualRoomView() }
                    .tabItem { Label("Rooms", systemImage: "rectangle.and.pencil.and.ellipsis") }

                NavigationView { LLMView() }
                    .tabItem { Label("LLM", systemImage: "brain.head.profile") }
            }
        }
    }
}

#Preview {
    ContentView()
}
