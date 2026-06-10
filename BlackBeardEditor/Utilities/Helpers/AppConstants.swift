//
//  Constants.swift
//  BlackBeardEditor
//
//  Created by Butt Simpson on 27.12.2025.
//

import Foundation
import SwiftUI

// MARK: - App Constants
struct AppConstants {
    
    // MARK: - App Information
    struct App {
        static let name = "Black Beard Editor"
        static let technicalName = "BlackBeardEditor"
        static let version = "1.0.0"
        static let bundleIdentifier = "shkurko.BlackBeardEditor"
        static let appGroup = "group.com.markdowneditor"
        static let appSupportFolderName = "BlackBeardEditor"
        static let legacyAppSupportFolderName = "Beardy2"

        static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let newDir = base.appendingPathComponent(appSupportFolderName, isDirectory: true)
            let legacyDir = base.appendingPathComponent(legacyAppSupportFolderName, isDirectory: true)
            if !fileManager.fileExists(atPath: newDir.path),
               fileManager.fileExists(atPath: legacyDir.path) {
                try? fileManager.moveItem(at: legacyDir, to: newDir)
            }
            if !fileManager.fileExists(atPath: newDir.path) {
                try? fileManager.createDirectory(at: newDir, withIntermediateDirectories: true)
            }
            return newDir
        }
    }
    
    // MARK: - File Types
    struct FileTypes {
        static let markdown = ["md", "markdown"]
        static let text = ["txt", "text"]
        static let allSupported = markdown + text
        
        static let markdownUTI = "net.daringfireball.markdown"
        static let textUTI = "public.plain-text"
    }
    
    // MARK: - Default Values
    struct Defaults {
        // Editor
        static let fontSize: CGFloat = 16
        static let lineHeight: CGFloat = 1.6
        static let fontFamily = "SF Mono"
        static let tabSize = 4
        
        // Window
        static let windowWidth: CGFloat = 1200
        static let windowHeight: CGFloat = 800
        static let minWindowWidth: CGFloat = 800
        static let minWindowHeight: CGFloat = 600
        
        // Sidebar
        static let sidebarWidth: CGFloat = 250
        static let minSidebarWidth: CGFloat = 200
        static let maxSidebarWidth: CGFloat = 400
        
        // Outline
        static let outlineWidth: CGFloat = 200
        
        // Auto-save
        static let autoSaveInterval: TimeInterval = 30
        
        // Recent files limit
        static let maxRecentFiles = 10
    }
    
    /// Reads a boolean UserDefaults value with an explicit default when the key was never set.
    /// Prefer `register(defaults:)` at launch; this guards `bool(forKey:)` which returns `false` for missing keys.
    static func boolSetting(forKey key: String, default defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }

    static func doubleSetting(forKey key: String, default defaultValue: Double) -> Double {
        if let value = UserDefaults.standard.object(forKey: key) as? Double { return value }
        if let value = UserDefaults.standard.object(forKey: key) as? NSNumber { return value.doubleValue }
        return defaultValue
    }

    static func intSetting(forKey key: String, default defaultValue: Int) -> Int {
        if let value = UserDefaults.standard.object(forKey: key) as? Int { return value }
        if let value = UserDefaults.standard.object(forKey: key) as? NSNumber { return value.intValue }
        return defaultValue
    }

    static var isPreviewSyncScrollEnabled: Bool {
        boolSetting(forKey: Keys.previewSyncScroll, default: true)
    }

    static var isRecoveryBackupEnabled: Bool {
        boolSetting(forKey: Keys.recoveryBackupEnabled, default: true)
    }

    static var restoreOpenFilesOnLaunch: Bool {
        boolSetting(forKey: Keys.restoreOpenFilesOnLaunch, default: true)
    }

    static var warnBeforeClosingUnsaved: Bool {
        boolSetting(forKey: Keys.warnBeforeClosingUnsaved, default: true)
    }

    enum StartupAction: String, CaseIterable, Identifiable {
        case welcome
        case last
        case new

        var id: String { rawValue }

        var label: String {
            switch self {
            case .welcome: return "Show Welcome Screen"
            case .last: return "Open Last Document"
            case .new: return "Create New Document"
            }
        }
    }

    static var startupAction: StartupAction {
        let raw = UserDefaults.standard.string(forKey: Keys.startupAction) ?? StartupAction.welcome.rawValue
        return StartupAction(rawValue: raw) ?? .welcome
    }

    // MARK: - User Defaults Keys
    struct Keys {
        // Documents
        static let recentDocuments = "recentDocuments"
        static let favorites = "favorites"
        static let folders = "folders"
        static let lastOpenedDocument = "lastOpenedDocument"
        static let startupAction = "startupAction"
        static let recoveryBackupEnabled = "recoveryBackupEnabled"
        static let restoreOpenFilesOnLaunch = "restoreOpenFilesOnLaunch"
        static let warnBeforeClosingUnsaved = "warnBeforeClosingUnsaved"
        
        // Editor Settings
        static let editorFontSize = "editorFontSize"
        static let editorLineHeight = "editorLineHeight"
        static let editorFontFamily = "editorFontFamily"
        static let showLineNumbers = "showLineNumbers"
        static let highlightCurrentLine = "highlightCurrentLine"
        static let indentSize = "indentSize"
        static let useSpacesForTabs = "useSpacesForTabs"
        
        // Typing Settings
        static let spellCheckEnabled = "spellCheckEnabled"
        static let grammarCheckEnabled = "grammarCheckEnabled"
        static let autoCapitalizationEnabled = "autoCapitalizationEnabled"
        static let smartQuotesEnabled = "smartQuotesEnabled"
        static let smartDashesEnabled = "smartDashesEnabled"
        
        // Appearance
        static let previewTheme = "previewTheme"
        static let themeFamily = "themeFamily"
        static let previewSyncScroll = "previewSyncScroll"
        static let codeBlockTheme = "codeBlockTheme"
        static let codeThemeAutomatic = "codeThemeAutomatic"
        static let isDarkMode = "isDarkMode"
        static let showCodeLineNumbers = "showCodeLineNumbers"
        static let focusDimInactiveLines = "focusDimInactiveLines"
        static let focusHideToolbar = "focusHideToolbar"
        static let focusHideSidebar = "focusHideSidebar"
        static let focusHideOutline = "focusHideOutline"
        static let followSystemAppearance = "followSystemAppearance"
        
        // Export
        static let exportImageFormat = "exportImageFormat"
        static let exportPDFMargins = "exportPDFMargins"
        static let usePandocForDocxExport = "usePandocForDocxExport"
        
        // View State
        static let sidebarVisible = "sidebarVisible"
        static let sidebarPanelWidth = "sidebarPanelWidth"
        static let outlineVisible = "outlineVisible"
        static let outlinePanelWidth = "outlinePanelWidth"
        static let viewMode = "viewMode"
        static let focusMode = "focusMode"
        static let typewriterMode = "typewriterMode"
        
        // Auto-save
        static let autoSaveEnabled = "autoSaveEnabled"
        static let autoSaveInterval = "autoSaveInterval"
    }
    
    // MARK: - Markdown Syntax
    struct Markdown {
        // Headers
        static let h1Prefix = "# "
        static let h2Prefix = "## "
        static let h3Prefix = "### "
        static let h4Prefix = "#### "
        static let h5Prefix = "##### "
        static let h6Prefix = "###### "
        
        // Formatting
        static let boldMarker = "**"
        static let italicMarker = "*"
        static let strikethroughMarker = "~~"
        static let inlineCodeMarker = "`"
        static let codeBlockMarker = "```"
        
        // Lists
        static let bulletListPrefix = "- "
        static let orderedListPrefix = "1. "
        static let taskListUnchecked = "- [ ] "
        static let taskListChecked = "- [x] "
        
        // Other
        static let blockquotePrefix = "> "
        static let horizontalRule = "---"
        static let linkTemplate = "[text](url)"
        static let imageTemplate = "![alt](url)"
        
        // Table
        static let tableTemplate = """
        | Column 1 | Column 2 | Column 3 |
        |----------|----------|----------|
        | Cell 1   | Cell 2   | Cell 3   |
        """
        
        // Code block template
        static let codeBlockTemplate = """
        ```language
        code here
        ```
        """
    }
    
    // MARK: - Keyboard Shortcuts
    struct Shortcuts {
        // File operations
        static let newDocument = "⌘N"
        static let openDocument = "⌘O"
        static let saveDocument = "⌘S"
        static let saveAs = "⇧⌘S"
        static let exportPDF = "⌘E"
        
        // Edit operations
        static let undo = "⌘Z"
        static let redo = "⇧⌘Z"
        static let cut = "⌘X"
        static let copy = "⌘C"
        static let paste = "⌘V"
        static let selectAll = "⌘A"
        static let find = "⌘F"
        static let replace = "⌥⌘F"
        
        // Formatting
        static let bold = "⌘B"
        static let italic = "⌘I"
        static let strikethrough = "⇧⌘S"
        static let inlineCode = "⌘`"
        static let codeBlock = "⇧⌘`"
        static let link = "⌘K"
        static let image = "⇧⌘I"
        
        // Headings
        static let heading1 = "⌘1"
        static let heading2 = "⌘2"
        static let heading3 = "⌘3"
        static let heading4 = "⌘4"
        static let heading5 = "⌘5"
        static let heading6 = "⌘6"
        
        // View
        static let toggleSidebar = "⌘\\"
        static let toggleOutline = "⇧⌘O"
        static let editMode = "⌘/"
        static let liveMode = "⇧⌘L"
        static let previewMode = "⇧⌘P"
        static let splitMode = "⌃⌘S"
        static let diffMode = "⌥⌘D"
        
        // Other
        static let preferences = "⌘,"
        static let keyboardShortcuts = "⌘K"
    }
    
    // MARK: - Colors
    struct Colors {
        // Accent colors
        static let primary = Color.blue
        static let secondary = Color.gray
        static let success = Color.green
        static let warning = Color.orange
        static let danger = Color.red
        
        // Editor colors
        static let editorBackground = Color(NSColor.textBackgroundColor)
        static let editorText = Color(NSColor.textColor)
        static let editorSelection = Color(NSColor.selectedTextBackgroundColor)
        static let editorCursor = Color(NSColor.controlAccentColor)
        
        // Syntax highlighting (light theme)
        struct Light {
            static let heading = Color(hex: "#0969DA")
            static let bold = Color(hex: "#24292F")
            static let italic = Color(hex: "#57606A")
            static let code = Color(hex: "#CF222E")
            static let link = Color(hex: "#0969DA")
            static let quote = Color(hex: "#57606A")
        }
        
        // Syntax highlighting (dark theme)
        struct Dark {
            static let heading = Color(hex: "#58A6FF")
            static let bold = Color(hex: "#E6EDF3")
            static let italic = Color(hex: "#8B949E")
            static let code = Color(hex: "#FF7B72")
            static let link = Color(hex: "#58A6FF")
            static let quote = Color(hex: "#8B949E")
        }
    }
    
    // MARK: - Fonts
    struct Fonts {
        static let monospacedFonts = [
            "SF Mono",
            "Menlo",
            "Monaco",
            "Courier New",
            "Source Code Pro",
            "Fira Code",
            "JetBrains Mono",
            "IBM Plex Mono"
        ]
        
        static let systemFonts = [
            "SF Pro",
            "Helvetica Neue",
            "Arial"
        ]
    }
    
    // MARK: - Themes
    struct Themes {
        static let availableThemes = [
            "GitHub",
            "GitHub Dark",
            "Minimal",
            "Solarized Light",
            "Solarized Dark",
            "One Dark",
            "Dracula"
        ]
        
        static let codeThemes = [
            "github",
            "github-dark",
            "monokai",
            "dracula",
            "atom-one-dark",
            "atom-one-light",
            "vs",
            "vs2015",
            "xcode"
        ]
    }
    
    // MARK: - Export
    struct Export {
        static let imageFormats = ["PNG", "JPEG", "SVG", "WebP"]
        static let paperSizes = ["Letter", "A4", "Legal"]
        
        static let defaultPDFMargins: CGFloat = 72 // 1 inch
        static let defaultImageQuality = 90
    }
    
    // MARK: - URLs
    struct URLs {
        // Подсветка кода — локально в бандле (HighlightJS/). CDN не используется.
        static let highlightJSBundled = true
        
        static let documentation = "https://beardyeditor.com/en/guide.html"
        static let support = "https://beardyeditor.com/en/"
        static let website = "https://beardyeditor.com"
    }
    
    // MARK: - Animations
    struct Animations {
        static let defaultDuration: TimeInterval = 0.3
        static let fastDuration: TimeInterval = 0.15
        static let slowDuration: TimeInterval = 0.5
        
        static let springResponse: Double = 0.3
        static let springDamping: Double = 0.7
    }
    
    // MARK: - Validation
    struct Validation {
        static let maxFileSize: Int64 = 10 * 1024 * 1024 // 10 MB
        static let maxDocumentLength = 1_000_000 // 1 million characters
    }
}
