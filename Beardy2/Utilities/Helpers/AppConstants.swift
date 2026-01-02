//
//  Constants.swift
//  Beardy2
//
//  Created by Butt Simpson on 27.12.2025.
//

import Foundation
import SwiftUI

// MARK: - App Constants
struct AppConstants {
    
    // MARK: - App Information
    struct App {
        static let name = "Markdown Editor"
        static let version = "1.0.0"
        static let bundleIdentifier = "com.markdowneditor.app"
        static let appGroup = "group.com.markdowneditor"
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
    
    // MARK: - User Defaults Keys
    struct Keys {
        // Documents
        static let recentDocuments = "recentDocuments"
        static let favorites = "favorites"
        static let folders = "folders"
        static let lastOpenedDocument = "lastOpenedDocument"
        
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
        static let previewSyncScroll = "previewSyncScroll"
        static let codeBlockTheme = "codeBlockTheme"
        static let isDarkMode = "isDarkMode"
        
        // Export
        static let exportImageFormat = "exportImageFormat"
        static let exportPDFMargins = "exportPDFMargins"
        
        // View State
        static let sidebarVisible = "sidebarVisible"
        static let outlineVisible = "outlineVisible"
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
        static let toggleSourceMode = "⌘/"
        static let focusMode = "⇧⌘F"
        static let typewriterMode = "⇧⌘T"
        
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
        static let highlightJS = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"
        static let highlightCSS = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/"
        
        static let documentation = "https://docs.markdowneditor.com"
        static let support = "https://support.markdowneditor.com"
        static let website = "https://markdowneditor.com"
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
