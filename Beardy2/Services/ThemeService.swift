//
//  ThemeService.swift
//  Beardy2
//
//  Created by Butt Simpson on 28.12.2025.
//

import Foundation
import SwiftUI
import AppKit
import Combine

// MARK: - Theme Service
class ThemeService: ObservableObject {
    
    static let shared = ThemeService()
    
    @Published var currentTheme: EditorTheme = .github
    @Published var currentCodeTheme: CodeTheme = .githubDark
    @Published var isDarkMode: Bool = false
    
    private init() {
        loadThemePreferences()
        setupSystemThemeObserver()
    }
    
    // MARK: - Editor Themes
    enum EditorTheme: String, CaseIterable, Identifiable {
        case github = "GitHub"
        case githubDark = "GitHub Dark"
        case minimal = "Minimal"
        case solarizedLight = "Solarized Light"
        case solarizedDark = "Solarized Dark"
        case oneDark = "One Dark"
        case dracula = "Dracula"
        case nord = "Nord"
        
        var id: String { rawValue }
        
        var displayName: String { rawValue }
        
        var isDark: Bool {
            switch self {
            case .github, .minimal, .solarizedLight:
                return false
            case .githubDark, .solarizedDark, .oneDark, .dracula, .nord:
                return true
            }
        }
        
        var colors: ThemeColors {
            switch self {
            case .github:
                return ThemeColors(
                    background: Color(hex: "#ffffff"),
                    text: Color(hex: "#24292e"),
                    secondaryText: Color(hex: "#6a737d"),
                    heading: Color(hex: "#0969DA"),
                    link: Color(hex: "#0366d6"),
                    code: Color(hex: "#f6f8fa"),
                    codeText: Color(hex: "#e36209"),
                    selection: Color(hex: "#b3d7ff"),
                    border: Color(hex: "#e1e4e8")
                )
            case .githubDark:
                return ThemeColors(
                    background: Color(hex: "#0d1117"),
                    text: Color(hex: "#c9d1d9"),
                    secondaryText: Color(hex: "#8b949e"),
                    heading: Color(hex: "#58a6ff"),
                    link: Color(hex: "#58a6ff"),
                    code: Color(hex: "#161b22"),
                    codeText: Color(hex: "#ff7b72"),
                    selection: Color(hex: "#264f78"),
                    border: Color(hex: "#30363d")
                )
            case .minimal:
                return ThemeColors(
                    background: Color(hex: "#fefefe"),
                    text: Color(hex: "#333333"),
                    secondaryText: Color(hex: "#888888"),
                    heading: Color(hex: "#111111"),
                    link: Color(hex: "#0066cc"),
                    code: Color(hex: "#f5f5f5"),
                    codeText: Color(hex: "#d73a49"),
                    selection: Color(hex: "#e0e0e0"),
                    border: Color(hex: "#dddddd")
                )
            case .solarizedLight:
                return ThemeColors(
                    background: Color(hex: "#fdf6e3"),
                    text: Color(hex: "#657b83"),
                    secondaryText: Color(hex: "#93a1a1"),
                    heading: Color(hex: "#268bd2"),
                    link: Color(hex: "#268bd2"),
                    code: Color(hex: "#eee8d5"),
                    codeText: Color(hex: "#dc322f"),
                    selection: Color(hex: "#eee8d5"),
                    border: Color(hex: "#eee8d5")
                )
            case .solarizedDark:
                return ThemeColors(
                    background: Color(hex: "#002b36"),
                    text: Color(hex: "#839496"),
                    secondaryText: Color(hex: "#586e75"),
                    heading: Color(hex: "#268bd2"),
                    link: Color(hex: "#2aa198"),
                    code: Color(hex: "#073642"),
                    codeText: Color(hex: "#dc322f"),
                    selection: Color(hex: "#073642"),
                    border: Color(hex: "#073642")
                )
            case .oneDark:
                return ThemeColors(
                    background: Color(hex: "#282c34"),
                    text: Color(hex: "#abb2bf"),
                    secondaryText: Color(hex: "#5c6370"),
                    heading: Color(hex: "#61afef"),
                    link: Color(hex: "#61afef"),
                    code: Color(hex: "#21252b"),
                    codeText: Color(hex: "#e06c75"),
                    selection: Color(hex: "#3e4451"),
                    border: Color(hex: "#181a1f")
                )
            case .dracula:
                return ThemeColors(
                    background: Color(hex: "#282a36"),
                    text: Color(hex: "#f8f8f2"),
                    secondaryText: Color(hex: "#6272a4"),
                    heading: Color(hex: "#bd93f9"),
                    link: Color(hex: "#8be9fd"),
                    code: Color(hex: "#44475a"),
                    codeText: Color(hex: "#ff79c6"),
                    selection: Color(hex: "#44475a"),
                    border: Color(hex: "#44475a")
                )
            case .nord:
                return ThemeColors(
                    background: Color(hex: "#2e3440"),
                    text: Color(hex: "#d8dee9"),
                    secondaryText: Color(hex: "#4c566a"),
                    heading: Color(hex: "#88c0d0"),
                    link: Color(hex: "#88c0d0"),
                    code: Color(hex: "#3b4252"),
                    codeText: Color(hex: "#bf616a"),
                    selection: Color(hex: "#434c5e"),
                    border: Color(hex: "#3b4252")
                )
            }
        }
    }
    
    // MARK: - Code Themes
    enum CodeTheme: String, CaseIterable, Identifiable {
        case github = "github"
        case githubDark = "github-dark"
        case monokai = "monokai"
        case dracula = "dracula"
        case atomOneDark = "atom-one-dark"
        case atomOneLight = "atom-one-light"
        case vs = "vs"
        case vs2015 = "vs2015"
        case xcode = "xcode"
        case solarizedLight = "solarized-light"
        case solarizedDark = "solarized-dark"
        
        var id: String { rawValue }
        
        var displayName: String {
            return rawValue.split(separator: "-")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
        
        var cdnURL: String {
            return "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/\(rawValue).min.css"
        }
    }
    
    // MARK: - Theme Colors
    struct ThemeColors {
        let background: Color
        let text: Color
        let secondaryText: Color
        let heading: Color
        let link: Color
        let code: Color
        let codeText: Color
        let selection: Color
        let border: Color
        
        // Convert to NSColor for AppKit
        var nsBackground: NSColor { NSColor(background) }
        var nsText: NSColor { NSColor(text) }
        var nsSecondaryText: NSColor { NSColor(secondaryText) }
        var nsHeading: NSColor { NSColor(heading) }
        var nsLink: NSColor { NSColor(link) }
        var nsCode: NSColor { NSColor(code) }
        var nsCodeText: NSColor { NSColor(codeText) }
        var nsSelection: NSColor { NSColor(selection) }
        var nsBorder: NSColor { NSColor(border) }
    }
    
    // MARK: - Theme Management
    func applyTheme(_ theme: EditorTheme) {
        currentTheme = theme
        isDarkMode = theme.isDark
        
        // Apply to app appearance
        NSApp.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        
        // Save preference
        UserDefaults.standard.set(theme.rawValue, forKey: AppConstants.Keys.previewTheme)
        
        // Post notification for updates
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }
    
    func applyCodeTheme(_ codeTheme: CodeTheme) {
        currentCodeTheme = codeTheme
        
        // Save preference
        UserDefaults.standard.set(codeTheme.rawValue, forKey: AppConstants.Keys.codeBlockTheme)
        
        // Post notification
        NotificationCenter.default.post(name: .codeThemeDidChange, object: nil)
    }
    
    func toggleDarkMode() {
        isDarkMode.toggle()
        
        // Apply appropriate theme
        if isDarkMode {
            applyTheme(.githubDark)
        } else {
            applyTheme(.github)
        }
    }
    
    // MARK: - System Theme Observer
    private func setupSystemThemeObserver() {
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(systemThemeChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }
    
    @objc private func systemThemeChanged() {
        // Detect current system theme
        let appearance = NSApp.effectiveAppearance.name.rawValue
        isDarkMode = appearance.contains("Dark")
    }
    
    // MARK: - Load/Save Preferences
    private func loadThemePreferences() {
        // Load editor theme
        if let savedTheme = UserDefaults.standard.string(forKey: AppConstants.Keys.previewTheme),
           let theme = EditorTheme(rawValue: savedTheme) {
            currentTheme = theme
            isDarkMode = theme.isDark
        }
        
        // Load code theme
        if let savedCodeTheme = UserDefaults.standard.string(forKey: AppConstants.Keys.codeBlockTheme),
           let codeTheme = CodeTheme(rawValue: savedCodeTheme) {
            currentCodeTheme = codeTheme
        }
    }
    
    // MARK: - CSS Generation
    func generateCSS(for theme: EditorTheme) -> String {
        let colors = theme.colors
        
        return """
        body {
            background-color: \(colors.background.toHex());
            color: \(colors.text.toHex());
        }
        
        h1, h2, h3, h4, h5, h6 {
            color: \(colors.heading.toHex());
        }
        
        a {
            color: \(colors.link.toHex());
        }
        
        code {
            background-color: \(colors.code.toHex());
            color: \(colors.codeText.toHex());
        }
        
        pre {
            background-color: \(colors.code.toHex());
        }
        
        blockquote {
            color: \(colors.secondaryText.toHex());
            border-left-color: \(colors.border.toHex());
        }
        
        ::selection {
            background-color: \(colors.selection.toHex());
        }
        """
    }
    
    // MARK: - Export Theme
    func exportTheme(_ theme: EditorTheme, to url: URL) throws {
        let css = generateCSS(for: theme)
        try css.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Import Custom Theme
    func importCustomTheme(from url: URL) throws {
        // Load CSS and create custom theme
        let css = try String(contentsOf: url, encoding: .utf8)
        // Parse CSS and create theme colors
        // This would require a CSS parser - simplified for now
        print("Imported theme from: \(url)")
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let themeDidChange = Notification.Name("themeDidChange")
    static let codeThemeDidChange = Notification.Name("codeThemeDidChange")
}

// MARK: - Color Extensions
extension Color {
    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components else {
            return "#000000"
        }
        
        let r = Int(components[0] * 255.0)
        let g = Int(components[1] * 255.0)
        let b = Int(components[2] * 255.0)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Theme Picker View
struct ThemePickerView: View {
    @ObservedObject var themeService: ThemeService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Editor Theme")
                .font(.headline)
            
            ForEach(ThemeService.EditorTheme.allCases) { theme in
                ThemeOptionRow(
                    theme: theme,
                    isSelected: themeService.currentTheme == theme
                ) {
                    themeService.applyTheme(theme)
                }
            }
            
//            Divider()
//            
//            Text("Code Highlighting")
//                .font(.headline)
//            
//            Picker("Code Theme", selection: $themeService.currentCodeTheme) {
//                ForEach(ThemeService.CodeTheme.allCases) { codeTheme in
//                    Text(codeTheme.displayName).tag(codeTheme)
//                }
//            }
//            .onChange(of: themeService.currentCodeTheme) { newTheme, _ in
//                themeService.applyCodeTheme(newTheme)
//            }
        }
        .padding()
    }
}

struct ThemeOptionRow: View {
    let theme: ThemeService.EditorTheme
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                // Theme preview colors
                HStack(spacing: 4) {
                    Circle()
                        .fill(theme.colors.background)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(theme.colors.border, lineWidth: 1)
                        )
                    
                    Circle()
                        .fill(theme.colors.heading)
                        .frame(width: 20, height: 20)
                    
                    Circle()
                        .fill(theme.colors.link)
                        .frame(width: 20, height: 20)
                }
                
                Text(theme.displayName)
                    .font(.system(size: 13))
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ThemePickerView_Previews: PreviewProvider {
    static var previews: some View {
        ThemePickerView(themeService: ThemeService.shared)
            .frame(width: 400, height: 600)
    }
}
