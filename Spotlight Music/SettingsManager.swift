//
//  SettingsManager.swift
//  Spotlight Music
//
//  Created by Shubham Kumar on 10/08/25.
//

import Foundation
import SwiftUI
import ServiceManagement
import AppKit

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum WindowSize: String, CaseIterable {
    case compact = "compact"
    case medium = "medium"
    case large = "large"
    
    var width: CGFloat {
        switch self {
        case .compact: return 560
        case .medium: return 640
        case .large: return 720
        }
    }
    
    var displayName: String {
        switch self {
        case .compact: return "Compact (560px)"
        case .medium: return "Medium (640px)"
        case .large: return "Large (720px)"
        }
    }
}

enum AudioQuality: String, CaseIterable {
    case auto = "auto"
    case high = "high"
    case medium = "medium"
    case low = "low"
    
    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .high: return "High (320kbps)"
        case .medium: return "Medium (160kbps)"
        case .low: return "Low (96kbps)"
        }
    }
}

enum SearchResultsLimit: Int, CaseIterable {
    case ten = 10
    case twenty = 20
    case fifty = 50
    case hundred = 100
    
    var displayName: String {
        return "\(self.rawValue) results"
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var launchAtLogin: Bool {
        didSet { 
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            setLaunchAtLogin(launchAtLogin)
        }
    }
    
    @Published var showInMenuBar: Bool {
        didSet { 
            UserDefaults.standard.set(showInMenuBar, forKey: "showInMenuBar")
            // Menu bar visibility is handled by the system
        }
    }
    
    @Published var showInDock: Bool {
        didSet { 
            UserDefaults.standard.set(showInDock, forKey: "showInDock")
            // Don't immediately update app visibility to avoid focus issues
            // The change will take effect on next app launch
        }
    }
    
    @Published var appearanceMode: AppearanceMode {
        didSet { 
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyAppearanceMode()
        }
    }
    
    @Published var windowSize: WindowSize {
        didSet { UserDefaults.standard.set(windowSize.rawValue, forKey: "windowSize") }
    }
    
    @Published var audioQuality: AudioQuality {
        didSet { UserDefaults.standard.set(audioQuality.rawValue, forKey: "audioQuality") }
    }
    
    @Published var autoPlayNext: Bool {
        didSet { UserDefaults.standard.set(autoPlayNext, forKey: "autoPlayNext") }
    }
    
    @Published var searchResultsLimit: SearchResultsLimit {
        didSet { UserDefaults.standard.set(searchResultsLimit.rawValue, forKey: "searchResultsLimit") }
    }
    
    @Published var enableAnimations: Bool {
        didSet { UserDefaults.standard.set(enableAnimations, forKey: "enableAnimations") }
    }
    
    @Published var showThumbnails: Bool {
        didSet { UserDefaults.standard.set(showThumbnails, forKey: "showThumbnails") }
    }
    
    @Published var enableKeyboardShortcuts: Bool {
        didSet { UserDefaults.standard.set(enableKeyboardShortcuts, forKey: "enableKeyboardShortcuts") }
    }
    
    private init() {
        // Load saved settings or use defaults
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.showInMenuBar = UserDefaults.standard.object(forKey: "showInMenuBar") as? Bool ?? true
        self.showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        
        let appearanceModeString = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppearanceMode.system.rawValue
        self.appearanceMode = AppearanceMode(rawValue: appearanceModeString) ?? .system
        
        let windowSizeString = UserDefaults.standard.string(forKey: "windowSize") ?? WindowSize.medium.rawValue
        self.windowSize = WindowSize(rawValue: windowSizeString) ?? .medium
        
        let audioQualityString = UserDefaults.standard.string(forKey: "audioQuality") ?? AudioQuality.auto.rawValue
        self.audioQuality = AudioQuality(rawValue: audioQualityString) ?? .auto
        
        self.autoPlayNext = UserDefaults.standard.object(forKey: "autoPlayNext") as? Bool ?? true
        
        let searchResultsLimitInt = UserDefaults.standard.object(forKey: "searchResultsLimit") as? Int ?? SearchResultsLimit.twenty.rawValue
        self.searchResultsLimit = SearchResultsLimit(rawValue: searchResultsLimitInt) ?? .twenty
        
        self.enableAnimations = UserDefaults.standard.object(forKey: "enableAnimations") as? Bool ?? true
        self.showThumbnails = UserDefaults.standard.object(forKey: "showThumbnails") as? Bool ?? true
        self.enableKeyboardShortcuts = UserDefaults.standard.object(forKey: "enableKeyboardShortcuts") as? Bool ?? true
        
        // Apply initial settings
        applyInitialAppVisibility()
        applyAppearanceMode()
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            }
        } else {
            // For older macOS versions, we'll use a simpler approach
            print("Launch at login requires macOS 13.0 or later")
        }
    }
    
    private func applyInitialAppVisibility() {
        DispatchQueue.main.async {
            // Only apply the dock visibility setting on app launch
            // Changing it during runtime can cause focus issues
            if self.showInDock {
                NSApp.setActivationPolicy(.regular)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    private func applyAppearanceMode() {
        DispatchQueue.main.async {
            switch self.appearanceMode {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
    
    // Helper methods for other components to use
    func shouldShowThumbnails() -> Bool {
        return showThumbnails
    }
    
    func shouldEnableAnimations() -> Bool {
        return enableAnimations
    }
    
    func getMaxSearchResults() -> Int {
        return searchResultsLimit.rawValue
    }
    
    func resetToDefaults() {
        launchAtLogin = false
        showInMenuBar = true
        showInDock = true
        appearanceMode = .system
        windowSize = .medium
        audioQuality = .auto
        autoPlayNext = true
        searchResultsLimit = .twenty
        enableAnimations = true
        showThumbnails = true
        enableKeyboardShortcuts = true
    }
}