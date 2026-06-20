//
//  ThemeService.swift
//  BlackBeardEditor
//

import Foundation
import SwiftUI
import AppKit
import Combine

// MARK: - Code themes

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
        rawValue.split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    /// Локальный CSS в бандле (офлайн). Для WebView — `file://` URL.
    var bundledThemeURL: String {
        BundledHighlightJS.themeCSSFileURLString(for: self)
    }

    /// Совместимость: URL темы подсветки (локальный файл).
    var cdnURL: String { bundledThemeURL }

    var isDark: Bool {
        switch self {
        case .github, .atomOneLight, .vs, .xcode, .solarizedLight:
            return false
        default:
            return true
        }
    }

    /// Default hljs block background for this syntax theme (keeps token colors readable).
    var blockBackgroundHex: String {
        switch self {
        case .github, .vs, .xcode: return "#ffffff"
        case .atomOneLight: return "#fafafa"
        case .solarizedLight: return "#fdf6e3"
        case .githubDark: return "#0d1117"
        case .monokai: return "#272822"
        case .dracula: return "#282a36"
        case .atomOneDark: return "#282c34"
        case .vs2015: return "#1e1e1e"
        case .solarizedDark: return "#002b36"
        }
    }
}

// MARK: - Theme colors

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
    let tableHeader: Color
    let tableStripe: Color

    var nsBackground: NSColor { NSColor(background) }
    var nsText: NSColor { NSColor(text) }
}

// MARK: - Theme identity

struct EditorThemeIdentity: Equatable, Identifiable {
    let family: ThemeFamily
    let isDark: Bool

    var id: String { "\(family.rawValue)-\(isDark ? "dark" : "light")" }
    var colors: ThemeColors { family.colors(isDark: isDark) }
    var displayName: String { family.displayName }
}

enum ThemeFamily: String, CaseIterable, Identifiable {
    case github = "github"
    case minimal = "minimal"
    case solarized = "solarized"
    case oneDark = "oneDark"
    case dracula = "dracula"
    case nord = "nord"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .minimal: return "Minimal"
        case .solarized: return "Solarized"
        case .oneDark: return "One Dark"
        case .dracula: return "Dracula"
        case .nord: return "Nord"
        }
    }

    func colors(isDark: Bool) -> ThemeColors {
        switch self {
        case .github:
            return isDark
                ? ThemeColors(
                    background: Color(hex: "#0d1117"),
                    text: Color(hex: "#c9d1d9"),
                    secondaryText: Color(hex: "#8b949e"),
                    heading: Color(hex: "#58a6ff"),
                    link: Color(hex: "#58a6ff"),
                    code: Color(hex: "#161b22"),
                    codeText: Color(hex: "#ff7b72"),
                    selection: Color(hex: "#264f78"),
                    border: Color(hex: "#30363d"),
                    tableHeader: Color(hex: "#161b22"),
                    tableStripe: Color(hex: "#0d1117")
                )
                : ThemeColors(
                    background: Color(hex: "#ffffff"),
                    text: Color(hex: "#24292e"),
                    secondaryText: Color(hex: "#6a737d"),
                    heading: Color(hex: "#0969DA"),
                    link: Color(hex: "#0366d6"),
                    code: Color(hex: "#f6f8fa"),
                    codeText: Color(hex: "#cf222e"),
                    selection: Color(hex: "#b3d7ff"),
                    border: Color(hex: "#d0d7de"),
                    tableHeader: Color(hex: "#f6f8fa"),
                    tableStripe: Color(hex: "#ffffff")
                )

        case .minimal:
            return isDark
                ? ThemeColors(
                    background: Color(hex: "#1c1c1e"),
                    text: Color(hex: "#f2f2f7"),
                    secondaryText: Color(hex: "#98989d"),
                    heading: Color(hex: "#ffffff"),
                    link: Color(hex: "#0a84ff"),
                    code: Color(hex: "#2c2c2e"),
                    codeText: Color(hex: "#ff9f0a"),
                    selection: Color(hex: "#3a3a3c"),
                    border: Color(hex: "#48484a"),
                    tableHeader: Color(hex: "#2c2c2e"),
                    tableStripe: Color(hex: "#1c1c1e")
                )
                : ThemeColors(
                    background: Color(hex: "#fefefe"),
                    text: Color(hex: "#333333"),
                    secondaryText: Color(hex: "#888888"),
                    heading: Color(hex: "#111111"),
                    link: Color(hex: "#0066cc"),
                    code: Color(hex: "#f0f0f0"),
                    codeText: Color(hex: "#d73a49"),
                    selection: Color(hex: "#e8e8e8"),
                    border: Color(hex: "#dddddd"),
                    tableHeader: Color(hex: "#f5f5f5"),
                    tableStripe: Color(hex: "#fefefe")
                )

        case .solarized:
            return isDark
                ? ThemeColors(
                    background: Color(hex: "#002b36"),
                    text: Color(hex: "#839496"),
                    secondaryText: Color(hex: "#586e75"),
                    heading: Color(hex: "#268bd2"),
                    link: Color(hex: "#2aa198"),
                    code: Color(hex: "#073642"),
                    codeText: Color(hex: "#dc322f"),
                    selection: Color(hex: "#094656"),
                    border: Color(hex: "#094656"),
                    tableHeader: Color(hex: "#073642"),
                    tableStripe: Color(hex: "#002b36")
                )
                : ThemeColors(
                    background: Color(hex: "#fdf6e3"),
                    text: Color(hex: "#657b83"),
                    secondaryText: Color(hex: "#93a1a1"),
                    heading: Color(hex: "#268bd2"),
                    link: Color(hex: "#268bd2"),
                    code: Color(hex: "#eee8d5"),
                    codeText: Color(hex: "#dc322f"),
                    selection: Color(hex: "#eee8d5"),
                    border: Color(hex: "#d6cdb2"),
                    tableHeader: Color(hex: "#eee8d5"),
                    tableStripe: Color(hex: "#fdf6e3")
                )

        case .oneDark:
            return isDark
                ? ThemeColors(
                    background: Color(hex: "#282c34"),
                    text: Color(hex: "#abb2bf"),
                    secondaryText: Color(hex: "#5c6370"),
                    heading: Color(hex: "#61afef"),
                    link: Color(hex: "#61afef"),
                    code: Color(hex: "#21252b"),
                    codeText: Color(hex: "#e06c75"),
                    selection: Color(hex: "#3e4451"),
                    border: Color(hex: "#3e4451"),
                    tableHeader: Color(hex: "#21252b"),
                    tableStripe: Color(hex: "#282c34")
                )
                : ThemeColors(
                    background: Color(hex: "#fafafa"),
                    text: Color(hex: "#383a42"),
                    secondaryText: Color(hex: "#a0a1a7"),
                    heading: Color(hex: "#4078f2"),
                    link: Color(hex: "#4078f2"),
                    code: Color(hex: "#f0f0f1"),
                    codeText: Color(hex: "#e45649"),
                    selection: Color(hex: "#e5e5e6"),
                    border: Color(hex: "#d8d8da"),
                    tableHeader: Color(hex: "#f0f0f1"),
                    tableStripe: Color(hex: "#fafafa")
                )

        case .dracula:
            return isDark
                ? ThemeColors(
                    background: Color(hex: "#282a36"),
                    text: Color(hex: "#f8f8f2"),
                    secondaryText: Color(hex: "#6272a4"),
                    heading: Color(hex: "#bd93f9"),
                    link: Color(hex: "#8be9fd"),
                    code: Color(hex: "#44475a"),
                    codeText: Color(hex: "#ff79c6"),
                    selection: Color(hex: "#44475a"),
                    border: Color(hex: "#6272a4"),
                    tableHeader: Color(hex: "#44475a"),
                    tableStripe: Color(hex: "#282a36")
                )
                : ThemeColors(
                    background: Color(hex: "#f8f8ff"),
                    text: Color(hex: "#383a4a"),
                    secondaryText: Color(hex: "#7c7c9a"),
                    heading: Color(hex: "#7c4dff"),
                    link: Color(hex: "#0097a7"),
                    code: Color(hex: "#ede7f6"),
                    codeText: Color(hex: "#c2185b"),
                    selection: Color(hex: "#e8eaf6"),
                    border: Color(hex: "#d1c4e9"),
                    tableHeader: Color(hex: "#ede7f6"),
                    tableStripe: Color(hex: "#f8f8ff")
                )

        case .nord:
            return isDark
                ? ThemeColors(
                    background: Color(hex: "#2e3440"),
                    text: Color(hex: "#eceff4"),
                    secondaryText: Color(hex: "#d8dee9"),
                    heading: Color(hex: "#88c0d0"),
                    link: Color(hex: "#88c0d0"),
                    code: Color(hex: "#3b4252"),
                    codeText: Color(hex: "#bf616a"),
                    selection: Color(hex: "#434c5e"),
                    border: Color(hex: "#4c566a"),
                    tableHeader: Color(hex: "#3b4252"),
                    tableStripe: Color(hex: "#2e3440")
                )
                : ThemeColors(
                    background: Color(hex: "#eceff4"),
                    text: Color(hex: "#2e3440"),
                    secondaryText: Color(hex: "#4c566a"),
                    heading: Color(hex: "#5e81ac"),
                    link: Color(hex: "#5e81ac"),
                    code: Color(hex: "#e5e9f0"),
                    codeText: Color(hex: "#bf616a"),
                    selection: Color(hex: "#d8dee9"),
                    border: Color(hex: "#d8dee9"),
                    tableHeader: Color(hex: "#e5e9f0"),
                    tableStripe: Color(hex: "#eceff4")
                )
        }
    }

    func pairedCodeTheme(isDark: Bool) -> CodeTheme {
        switch self {
        case .github:
            return isDark ? .githubDark : .github
        case .minimal:
            return isDark ? .atomOneDark : .atomOneLight
        case .solarized:
            return isDark ? .solarizedDark : .solarizedLight
        case .oneDark:
            return isDark ? .atomOneDark : .atomOneLight
        case .dracula:
            return isDark ? .dracula : .vs
        case .nord:
            return isDark ? .atomOneDark : .xcode
        }
    }
}

// MARK: - Theme Service

class ThemeService: NSObject, ObservableObject {

    static let shared = ThemeService()

    @Published private(set) var themeFamily: ThemeFamily = .github
    @Published private(set) var isDarkMode: Bool = false
    @Published private(set) var currentCodeTheme: CodeTheme = .github
    @Published private(set) var isCodeThemeAutomatic: Bool = true
    @Published var followSystemAppearance: Bool = false

    var currentTheme: EditorThemeIdentity {
        EditorThemeIdentity(family: themeFamily, isDark: isDarkMode)
    }

    var colors: ThemeColors {
        currentTheme.colors
    }

    /// Background for fenced code blocks in the preview (matches syntax theme when manual).
    var codeBlockBackgroundHex: String {
        if isCodeThemeAutomatic {
            return colors.code.toHex()
        }
        return currentCodeTheme.blockBackgroundHex
    }

    var codeBlockBorderHex: String {
        colors.border.toHex()
    }

    var appearanceToken: String {
        "\(themeFamily.rawValue)-\(isDarkMode)-\(currentCodeTheme.rawValue)-\(isCodeThemeAutomatic)"
    }

    private override init() {
        super.init()
        loadThemePreferences()
        setupSystemThemeObserver()
        // Defer appearance until NSApp is ready (AppDelegate calls applyAppearance on launch).
    }

    // MARK: - Public API

    func selectThemeFamily(_ family: ThemeFamily) {
        disableFollowSystemAppearance()
        themeFamily = family
        applyAppearance()
    }

    func setDarkMode(_ isDark: Bool) {
        guard isDarkMode != isDark else { return }
        disableFollowSystemAppearance()
        isDarkMode = isDark
        applyAppearance()
    }

    func toggleDarkMode() {
        disableFollowSystemAppearance()
        isDarkMode.toggle()
        applyAppearance()
    }

    private func disableFollowSystemAppearance() {
        guard followSystemAppearance else { return }
        followSystemAppearance = false
        UserDefaults.standard.set(false, forKey: AppConstants.Keys.followSystemAppearance)
    }

    func selectCodeTheme(_ theme: CodeTheme, automatic: Bool = false) {
        isCodeThemeAutomatic = automatic
        if automatic {
            currentCodeTheme = themeFamily.pairedCodeTheme(isDark: isDarkMode)
        } else {
            currentCodeTheme = theme
        }
        savePreferences()
        EditorAppearanceSync.pushToEditor()
        NotificationCenter.default.post(name: .codeThemeDidChange, object: nil)
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }

    /// Applies editor + app chrome + code theme and persists settings.
    func applyAppearance(notify: Bool = true) {
        if isCodeThemeAutomatic {
            currentCodeTheme = themeFamily.pairedCodeTheme(isDark: isDarkMode)
        }

        // Editor first so it does not lag behind the app shell.
        EditorAppearanceSync.pushToEditor()

        if NSApp.isRunning {
            NSApp.appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
        }
        savePreferences()

        if notify {
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
            NotificationCenter.default.post(name: .codeThemeDidChange, object: nil)
        }
    }

    func setFollowSystemAppearance(_ enabled: Bool) {
        followSystemAppearance = enabled
        UserDefaults.standard.set(enabled, forKey: AppConstants.Keys.followSystemAppearance)
        if enabled {
            syncWithSystemAppearance()
        }
        applyAppearance()
    }

    func syncWithSystemAppearance() {
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDarkMode != isDark {
            isDarkMode = isDark
        }
    }

    private func setupSystemThemeObserver() {
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(systemThemeChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @objc private func systemThemeChanged() {
        guard followSystemAppearance else { return }
        syncWithSystemAppearance()
        applyAppearance()
    }

    func generateCSS(for theme: EditorThemeIdentity) -> String {
        generateCSS(colors: theme.colors)
    }

    func generateCSS(colors: ThemeColors) -> String {
        let bg = colors.background.toHex()
        let text = colors.text.toHex()
        let secondary = colors.secondaryText.toHex()
        let heading = colors.heading.toHex()
        let link = colors.link.toHex()
        let codeBg = colors.code.toHex()
        let codeText = colors.codeText.toHex()
        let selection = colors.selection.toHex()
        let border = colors.border.toHex()
        let tableHeader = colors.tableHeader.toHex()
        let tableStripe = colors.tableStripe.toHex()

        return """
        :root {
            --md-bg: \(bg);
            --md-text: \(text);
            --md-secondary: \(secondary);
            --md-heading: \(heading);
            --md-link: \(link);
            --md-code-bg: \(codeBg);
            --md-code-text: \(codeText);
            --md-selection: \(selection);
            --md-border: \(border);
            --md-divider: \(secondary);
            --md-table-header: \(tableHeader);
            --md-table-stripe: \(tableStripe);
        }

        html, body,
        #markdown-pane,
        #preview-content,
        #live-editor {
            background-color: var(--md-bg) !important;
            color: var(--md-text) !important;
        }

        #markdown-textarea {
            background-color: transparent !important;
            caret-color: var(--md-text);
            color: var(--md-text) !important;
        }

        #preview-content,
        #live-editor {
            line-height: var(--document-line-height-ratio, 1.6);
        }

        #preview-content .live-block,
        #live-editor .live-block,
        #preview-content p,
        #preview-content li,
        #live-editor p,
        #live-editor li {
            line-height: inherit;
        }

        #preview-content h1, #preview-content h2, #preview-content h3,
        #preview-content h4, #preview-content h5, #preview-content h6,
        #live-editor h1, #live-editor h2, #live-editor h3 {
            color: var(--md-heading);
            font-weight: 600;
        }

        #preview-content h1 { font-size: 2em; margin: 0.67em 0 0.4em; }
        #preview-content h2 { font-size: 1.5em; margin: 0.75em 0 0.4em; }
        #preview-content h3 { font-size: 1.25em; margin: 0.85em 0 0.35em; }

        #preview-content a, #live-editor a {
            color: var(--md-link);
            text-decoration: none;
        }
        #preview-content a:hover { text-decoration: underline; }

        #preview-content :not(pre) > code,
        #live-editor :not(pre) > code {
            font-family: 'SF Mono', Menlo, Monaco, Consolas, monospace;
            background-color: var(--md-code-bg) !important;
            color: var(--md-code-text) !important;
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 0.9em;
        }

        #preview-content pre,
        #live-editor pre {
            border-radius: 8px;
            overflow: auto;
            margin: 1em 0;
            border: 1px solid var(--md-border);
        }

        #preview-content pre:not(.hljs) {
            background-color: var(--md-code-bg) !important;
            padding: 16px;
        }

        #preview-content pre code,
        #live-editor pre code {
            background: transparent !important;
            background-color: transparent !important;
            color: inherit;
            padding: 0;
            display: block;
        }

        #preview-content pre.hljs,
        #live-editor pre.hljs {
            background-color: var(--md-code-bg) !important;
            padding: 14px 16px !important;
            margin: 1em 0;
        }

        #preview-content .code-fence-wrap,
        #live-editor .code-fence-wrap {
            margin: 0.5em 0;
        }

        #preview-content .code-fence-wrap pre.hljs,
        #live-editor .code-fence-wrap pre.hljs {
            margin: 0 !important;
            background-color: transparent !important;
        }

        #preview-content .code-fence-wrap pre.hljs.has-line-numbers,
        #live-editor .code-fence-wrap pre.hljs.has-line-numbers {
            padding: 8px 0 !important;
        }

        #preview-content table.hljs-ln,
        #live-editor table.hljs-ln {
            display: table !important;
            border-collapse: collapse;
            width: 100%;
            border: none !important;
        }

        #preview-content table.hljs-ln tbody,
        #live-editor table.hljs-ln tbody {
            display: table-row-group !important;
        }

        #preview-content table.hljs-ln tr,
        #live-editor table.hljs-ln tr {
            display: table-row !important;
        }

        #preview-content table.hljs-ln td.hljs-ln-numbers,
        #live-editor table.hljs-ln td.hljs-ln-numbers,
        #preview-content table.hljs-ln td.hljs-ln-code,
        #live-editor table.hljs-ln td.hljs-ln-code {
            display: table-cell !important;
            vertical-align: top;
            border: none !important;
            background: transparent !important;
        }

        #preview-content table.hljs-ln td.hljs-ln-numbers,
        #live-editor table.hljs-ln td.hljs-ln-numbers {
            color: var(--md-secondary) !important;
            white-space: nowrap;
            text-align: right;
            padding: 0 10px 0 12px !important;
            border-right: 1px solid var(--md-border);
            user-select: none;
        }

        #preview-content table.hljs-ln td.hljs-ln-code,
        #live-editor table.hljs-ln td.hljs-ln-code {
            padding: 0 12px 0 10px !important;
            white-space: pre;
        }

        #preview-content table.hljs-ln .hljs-ln-line,
        #live-editor table.hljs-ln .hljs-ln-line {
            display: inline;
            white-space: pre;
            padding: 0 !important;
            margin: 0 !important;
        }

        #preview-content pre.hljs code,
        #live-editor pre.hljs code,
        #preview-content pre.hljs code *,
        #live-editor pre.hljs code *,
        #preview-content pre.hljs .hljs,
        #live-editor pre.hljs .hljs {
            background: transparent !important;
            background-color: transparent !important;
        }

        #preview-content blockquote,
        #live-editor blockquote,
        #diff-content blockquote,
        #diff-content .diff-blockquote {
            margin: 0.5em 0;
            padding: 0.25em 0 0.25em 1em;
            border-left: 4px solid var(--md-divider);
            color: var(--md-secondary);
        }

        #preview-content ul, #preview-content ol,
        #live-editor ul, #live-editor ol {
            padding-left: 1.75em;
            margin: 0.5em 0;
        }

        #preview-content li { margin: 0.25em 0; }

        #preview-content hr,
        #live-editor hr,
        #diff-content hr {
            border: none;
            border-top: 1px solid var(--md-divider);
            margin: 2em 0;
        }

        .live-block[data-type="blockquote"] {
            border-left: 4px solid var(--md-divider);
        }

        .live-block[data-type="blockquote"] .bq-nested {
            border-left-color: var(--md-divider);
        }

        .live-block[data-type="hr"] {
            border-top-color: var(--md-divider);
        }

        #preview-content table.md-table {
            border-collapse: collapse;
            width: 100%;
            margin: 1em 0;
            font-size: 0.95em;
        }

        #preview-content table.md-table th,
        #preview-content table.md-table td {
            border: 1px solid var(--md-border);
            padding: 8px 12px;
            text-align: left;
        }

        #preview-content table.md-table thead,
        #preview-content table.md-table th {
            background-color: var(--md-table-header) !important;
            color: var(--md-heading);
            font-weight: 600;
        }

        #preview-content table.md-table tbody tr:nth-child(even) {
            background-color: var(--md-table-stripe);
        }

        #preview-content img {
            max-width: 100%;
            height: auto;
            border-radius: 4px;
        }

        ::selection {
            background-color: var(--md-selection);
        }

        #markdown-pane, #preview-pane {
            border-color: var(--md-border) !important;
        }
        """
    }

    // MARK: - Persistence

    private func savePreferences() {
        UserDefaults.standard.set(themeFamily.rawValue, forKey: AppConstants.Keys.themeFamily)
        UserDefaults.standard.set(isDarkMode, forKey: AppConstants.Keys.isDarkMode)
        UserDefaults.standard.set(currentCodeTheme.rawValue, forKey: AppConstants.Keys.codeBlockTheme)
        UserDefaults.standard.set(isCodeThemeAutomatic, forKey: AppConstants.Keys.codeThemeAutomatic)
        UserDefaults.standard.set(legacyThemeName(), forKey: AppConstants.Keys.previewTheme)
    }

    private func loadThemePreferences() {
        if let familyRaw = UserDefaults.standard.string(forKey: AppConstants.Keys.themeFamily),
           let family = ThemeFamily(rawValue: familyRaw) {
            themeFamily = family
        } else if let legacy = UserDefaults.standard.string(forKey: AppConstants.Keys.previewTheme) {
            migrateLegacyTheme(legacy)
        }

        if UserDefaults.standard.object(forKey: AppConstants.Keys.isDarkMode) != nil {
            isDarkMode = UserDefaults.standard.bool(forKey: AppConstants.Keys.isDarkMode)
        }

        if UserDefaults.standard.object(forKey: AppConstants.Keys.codeThemeAutomatic) != nil {
            isCodeThemeAutomatic = UserDefaults.standard.bool(forKey: AppConstants.Keys.codeThemeAutomatic)
        }

        if UserDefaults.standard.object(forKey: AppConstants.Keys.followSystemAppearance) != nil {
            followSystemAppearance = UserDefaults.standard.bool(forKey: AppConstants.Keys.followSystemAppearance)
        }

        if let codeRaw = UserDefaults.standard.string(forKey: AppConstants.Keys.codeBlockTheme),
           let code = CodeTheme(rawValue: codeRaw) {
            currentCodeTheme = code
        }
    }

    private func migrateLegacyTheme(_ name: String) {
        switch name {
        case "GitHub": themeFamily = .github; isDarkMode = false
        case "GitHub Dark": themeFamily = .github; isDarkMode = true
        case "Minimal": themeFamily = .minimal; isDarkMode = false
        case "Solarized Light": themeFamily = .solarized; isDarkMode = false
        case "Solarized Dark": themeFamily = .solarized; isDarkMode = true
        case "One Dark": themeFamily = .oneDark; isDarkMode = true
        case "Dracula": themeFamily = .dracula; isDarkMode = true
        case "Nord": themeFamily = .nord; isDarkMode = true
        default:
            themeFamily = .github
            isDarkMode = name.lowercased().contains("dark")
        }
    }

    private func legacyThemeName() -> String {
        "\(themeFamily.displayName)\(isDarkMode ? " Dark" : "")"
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let themeDidChange = Notification.Name("themeDidChange")
    static let codeThemeDidChange = Notification.Name("codeThemeDidChange")
}

// MARK: - Color hex

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

// MARK: - Theme Picker

struct ThemePickerView: View {
    @ObservedObject var themeService: ThemeService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Editor Theme")
                .font(.headline)

            ForEach(ThemeFamily.allCases) { family in
                ThemeFamilyRow(
                    family: family,
                    isSelected: themeService.themeFamily == family,
                    isDark: themeService.isDarkMode
                ) {
                    themeService.selectThemeFamily(family)
                }
            }

            Toggle("Dark appearance", isOn: Binding(
                get: { themeService.isDarkMode },
                set: { themeService.setDarkMode($0) }
            ))
            .padding(.top, 4)

            if themeService.followSystemAppearance {
                Text("Turn off “Follow system” above to set light/dark manually.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct ThemeFamilyRow: View {
    let family: ThemeFamily
    let isSelected: Bool
    let isDark: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var previewColors: ThemeColors {
        family.colors(isDark: isDark)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(previewColors.background)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(previewColors.border, lineWidth: 1))
                    Circle()
                        .fill(previewColors.heading)
                        .frame(width: 18, height: 18)
                    Circle()
                        .fill(previewColors.link)
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(family.displayName)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    Text(isDark ? "Dark variant" : "Light variant")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
