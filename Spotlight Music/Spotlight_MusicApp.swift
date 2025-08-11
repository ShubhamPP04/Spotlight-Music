//
//  Spotlight_MusicApp.swift
//  Spotlight Music
//
//  Created by Shubham Kumar on 10/08/25.
//

import SwiftUI

@main
struct Spotlight_MusicApp: App {
    @StateObject private var settings = SettingsManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(settings.appearanceMode.colorScheme)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
