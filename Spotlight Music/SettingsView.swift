//
//  SettingsView.swift
//  Spotlight Music
//
//  Created by Shubham Kumar on 10/08/25.
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    // Optional closure to allow the host window to be closed from the Done button
    var onClose: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Done") {
                    // If we're embedded in a standalone window, ask the host to close it
                    if let onClose { onClose() }
                    else { dismiss() }
                }
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.regularMaterial)
            
            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // General section
                    SettingsSection("General") {
                        SettingsRow(
                            icon: "power",
                            title: "Launch at Login",
                            subtitle: "Automatically start Spotlight Music when you log in"
                        ) {
                            Toggle("", isOn: $settings.launchAtLogin)
                                .toggleStyle(.switch)
                        }
                        
                        SettingsRow(
                            icon: "dock.rectangle",
                            title: "Show in Dock",
                            subtitle: "Display Spotlight Music icon in the Dock (requires restart)"
                        ) {
                            Toggle("", isOn: $settings.showInDock)
                                .toggleStyle(.switch)
                        }
                        
                        SettingsRow(
                            icon: "keyboard",
                            title: "Enable Keyboard Shortcuts",
                            subtitle: "Allow global keyboard shortcuts for app control"
                        ) {
                            Toggle("", isOn: $settings.enableKeyboardShortcuts)
                                .toggleStyle(.switch)
                        }
                    }
                    
                    // Appearance section
                    SettingsSection("Appearance") {
                        SettingsRow(
                            icon: "paintbrush",
                            title: "Theme",
                            subtitle: "Choose your preferred appearance"
                        ) {
                            Picker("", selection: $settings.appearanceMode) {
                                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                        
                        SettingsRow(
                            icon: "rectangle.resize",
                            title: "Window Size",
                            subtitle: "Default size for the search window"
                        ) {
                            Picker("", selection: $settings.windowSize) {
                                ForEach(WindowSize.allCases, id: \.self) { size in
                                    Text(size.displayName).tag(size)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 160)
                        }
                        
                        SettingsRow(
                            icon: "photo",
                            title: "Show Thumbnails",
                            subtitle: "Display album artwork and artist images"
                        ) {
                            Toggle("", isOn: $settings.showThumbnails)
                                .toggleStyle(.switch)
                        }
                        
                        SettingsRow(
                            icon: "sparkles",
                            title: "Enable Animations",
                            subtitle: "Smooth transitions and visual effects"
                        ) {
                            Toggle("", isOn: $settings.enableAnimations)
                                .toggleStyle(.switch)
                        }
                    }
                    
                    // Search & Playback section
                    SettingsSection("Search & Playback") {
                        SettingsRow(
                            icon: "magnifyingglass",
                            title: "Search Results Limit",
                            subtitle: "Maximum number of results to display"
                        ) {
                            Picker("", selection: $settings.searchResultsLimit) {
                                ForEach(SearchResultsLimit.allCases, id: \.self) { limit in
                                    Text(limit.displayName).tag(limit)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }
                        
                        SettingsRow(
                            icon: "speaker.wave.2",
                            title: "Audio Quality",
                            subtitle: "Preferred streaming quality"
                        ) {
                            Picker("", selection: $settings.audioQuality) {
                                ForEach(AudioQuality.allCases, id: \.self) { quality in
                                    Text(quality.displayName).tag(quality)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 140)
                        }
                        
                        SettingsRow(
                            icon: "goforward",
                            title: "Auto-play Next",
                            subtitle: "Automatically play the next song in queue"
                        ) {
                            Toggle("", isOn: $settings.autoPlayNext)
                                .toggleStyle(.switch)
                        }
                    }
                    
                    // Keyboard shortcuts section
                    SettingsSection("Keyboard Shortcuts") {
                        SettingsRow(
                            icon: "command",
                            title: "Show/Hide Window",
                            subtitle: "Global shortcut to toggle the search window"
                        ) {
                            Text("⌘ Space")
                                .font(.system(size: 13, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        SettingsRow(
                            icon: "gear",
                            title: "Settings",
                            subtitle: "Open settings window"
                        ) {
                            Text("⌘ ,")
                                .font(.system(size: 13, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    
                    // Advanced section
                    SettingsSection("Advanced") {
                        SettingsRow(
                            icon: "arrow.clockwise",
                            title: "Reset Settings",
                            subtitle: "Restore all settings to default values"
                        ) {
                            Button("Reset") {
                                settings.resetToDefaults()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        SettingsRow(
                            icon: "folder",
                            title: "Open Config Folder",
                            subtitle: "Access app configuration files"
                        ) {
                            Button("Open") {
                                openConfigFolder()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    
                    // About section
                    SettingsSection("About") {
                        SettingsRow(
                            icon: "info.circle",
                            title: "Version",
                            subtitle: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                        ) {
                            Button("Copy") {
                                let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("Spotlight Music v\(ver)", forType: .string)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        SettingsRow(
                            icon: "questionmark.circle",
                            title: "Support",
                            subtitle: "Get help and report issues"
                        ) {
                            Button("GitHub") {
                                if let url = URL(string: "https://github.com") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 600, height: 500)
        .background(.regularMaterial)
    }
    
    private func openConfigFolder() {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        if let appSupportURL = urls.first {
            let configURL = appSupportURL.appendingPathComponent("Spotlight Music")
            
            // Create directory if it doesn't exist
            try? fileManager.createDirectory(at: configURL, withIntermediateDirectories: true)
            
            NSWorkspace.shared.open(configURL)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            VStack(spacing: 1) {
                content
            }
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct SettingsRow<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let content: Content
    
    init(icon: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.system(size: 16))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}

#Preview {
    SettingsView()
}