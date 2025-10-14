//
//  ContentView.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/12/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var chat: ChatManager
    @State private var selectedTab = 0
    
    var body: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                Tab("Sessions", systemImage: "list.bullet.rectangle", value: 0) {
                    NavigationStack { SessionsView() }
                }
                Tab("Manual Room", systemImage: "rectangle.and.pencil.and.ellipsis", value: 1) {
                    NavigationStack { ManualRoomView() }
                }
                Tab("LLM", systemImage: "brain.head.profile", value: 2) {
                    NavigationStack { LLMView() }
                }
            }
            .onChange(of: chat.shouldNavigateToChat) { oldValue, newValue in
                if newValue {
                    print("[ContentView] 🚀 Push notification - switching to Sessions tab")
                    selectedTab = 0 // Switch to Sessions tab
                }
            }
        } else {
            // Fallback for older iOS: standard TabView with a dedicated Search tab
            TabView(selection: $selectedTab) {
                NavigationView { SessionsView() }
                    .tabItem { Label("Sessions", systemImage: "list.bullet.rectangle") }
                    .tag(0)

                NavigationView { ManualRoomView() }
                    .tabItem { Label("Rooms", systemImage: "rectangle.and.pencil.and.ellipsis") }
                    .tag(1)

                NavigationView { LLMView() }
                    .tabItem { Label("LLM", systemImage: "brain.head.profile") }
                    .tag(2)
            }
            .onChange(of: chat.shouldNavigateToChat) { oldValue, newValue in
                if newValue {
                    print("[ContentView] 🚀 Push notification - switching to Sessions tab")
                    selectedTab = 0 // Switch to Sessions tab
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
