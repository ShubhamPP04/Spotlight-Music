//
//  AppDelegate.swift
//  Spotlight Music
//
//  Created by Shubham Kumar on 10/08/25.
//

import SwiftUI
import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    static let shared = AppDelegate()
    private var settingsWindow: NSWindow?
    
    func openSettings() {
        // Close existing settings window if open
        if let existingWindow = settingsWindow {
            existingWindow.close()
            settingsWindow = nil
        }
        
        // Create a new settings window
        let settingsView = SettingsView(onClose: { [weak self] in
            // Close the window when Done is tapped
            self?.settingsWindow?.close()
        })
            .preferredColorScheme(SettingsManager.shared.appearanceMode.colorScheme)
        
        let hostingController = NSHostingController(rootView: settingsView)
        
        let newSettingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newSettingsWindow.title = "Settings"
        newSettingsWindow.contentViewController = hostingController
        newSettingsWindow.center()
        newSettingsWindow.isReleasedWhenClosed = false // Keep reference to prevent crash
        newSettingsWindow.delegate = self
        
        // Store reference and show
        settingsWindow = newSettingsWindow
        newSettingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Application setup code here
    }
}

// MARK: - NSWindowDelegate
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == settingsWindow else { return }
        
        // Clear delegate to prevent retain cycle
        window.delegate = nil
        
        // Clear the reference
        settingsWindow = nil
        
        // Note: Removed automatic relaunch - let the app continue running normally
    }
}