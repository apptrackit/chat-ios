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
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            SecuredContentView {
                ContentView()
                    .environmentObject(chat)
                    .onOpenURL { url in
                        chat.handleIncomingURL(url)
                    }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            chat.handleScenePhaseChange(newPhase)
        }
    }
}
