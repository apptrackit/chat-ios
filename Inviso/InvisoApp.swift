//
//  InvisoApp.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/12/25.
//

import SwiftUI
import BackgroundTasks

@main
struct InvisoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var chat = ChatManager.shared
    
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
    }
}
