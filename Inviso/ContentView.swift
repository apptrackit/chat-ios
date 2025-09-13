//
//  ContentView.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/12/25.
//

import SwiftUI

struct ContentView: View {
    @State private var search: String = ""

    var body: some View {
        if #available(iOS 18.0, *) {
            TabView {
                Tab("Sessions", systemImage: "list.bullet.rectangle") {
                    NavigationStack { SessionsView() }
                }
                Tab("Manual Room", systemImage: "rectangle.and.pencil.and.ellipsis") {
                    NavigationStack { ManualRoomView() }
                }
                Tab("Search", systemImage: "magnifyingglass", role: .search) {
                    NavigationStack { EmptyView() }
                }
            }
            .searchable(text: $search)
        } else {
            // Fallback for older iOS: standard TabView with a dedicated Search tab
            TabView {
                NavigationView { SessionsView() }
                    .tabItem { Label("Sessions", systemImage: "list.bullet.rectangle") }

                NavigationView { ManualRoomView() }
                    .tabItem { Label("Rooms", systemImage: "rectangle.and.pencil.and.ellipsis") }

                NavigationView { SearchView() }
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
            }
        }
    }
}

#Preview {
    ContentView()
}
