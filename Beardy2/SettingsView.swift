//
//  SettingsView.swift
//  Beardy2
//
//  Created by Butt Simpson on 27.12.2025.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("editorFontSize") private var editorFontSize: Double = 16
    @AppStorage("editorLineHeight") private var editorLineHeight: Double = 1.6
    @AppStorage("editorFontFamily") private var editorFontFamily: String = "SF Mono"
    @AppStorage("autoSaveEnabled") private var autoSaveEnabled: Bool = true
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30
    @AppStorage("spellCheckEnabled") private var spellCheckEnabled: Bool = true
    @AppStorage("grammarCheckEnabled") private var grammarCheckEnabled: Bool = true
    @AppStorage("autoCapitalizationEnabled") private var autoCapitalizationEnabled: Bool = false
    @AppStorage("smartQuotesEnabled") private var smartQuotesEnabled: Bool = false
    @AppStorage("smartDashesEnabled") private var smartDashesEnabled: Bool = false
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = false
    @AppStorage("highlightCurrentLine") private var highlightCurrentLine: Bool = true
    @AppStorage("indentSize") private var indentSize: Int = 4
    @AppStorage("useSpacesForTabs") private var useSpacesForTabs: Bool = true
    @AppStorage(AppConstants.Keys.previewSyncScroll) private var previewSyncScroll: Bool = true
    @AppStorage("exportImageFormat") private var exportImageFormat: String = "png"
    @AppStorage("exportPDFMargins") private var exportPDFMargins: Double = 72
    @AppStorage(ImageInsertionHelper.copyImagesToDocumentFolderKey) private var copyImagesToDocumentFolder: Bool = true
    
    @State private var selectedTab: SettingsTab = .general
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(
                autoSaveEnabled: $autoSaveEnabled,
                autoSaveInterval: $autoSaveInterval
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag(SettingsTab.general)
            
            EditorSettingsView(
                fontSize: $editorFontSize,
                lineHeight: $editorLineHeight,
                fontFamily: $editorFontFamily,
                showLineNumbers: $showLineNumbers,
                highlightCurrentLine: $highlightCurrentLine,
                indentSize: $indentSize,
                useSpacesForTabs: $useSpacesForTabs,
                copyImagesToDocumentFolder: $copyImagesToDocumentFolder
            )
            .tabItem {
                Label("Editor", systemImage: "doc.text")
            }
            .tag(SettingsTab.editor)
            
            TypingSettingsView(
                spellCheckEnabled: $spellCheckEnabled,
                grammarCheckEnabled: $grammarCheckEnabled,
                autoCapitalizationEnabled: $autoCapitalizationEnabled,
                smartQuotesEnabled: $smartQuotesEnabled,
                smartDashesEnabled: $smartDashesEnabled
            )
            .tabItem {
                Label("Typing", systemImage: "keyboard")
            }
            .tag(SettingsTab.typing)
            
            AppearanceSettingsView(previewSyncScroll: $previewSyncScroll)
            .tabItem {
                Label("Appearance", systemImage: "paintbrush")
            }
            .tag(SettingsTab.appearance)
            
            ExportSettingsView(
                imageFormat: $exportImageFormat,
                pdfMargins: $exportPDFMargins,
                copyImagesToDocumentFolder: $copyImagesToDocumentFolder
            )
            .tabItem {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .tag(SettingsTab.export)
        }
        .frame(width: 600, height: 450)
    }
}

enum SettingsTab: Hashable {
    case general
    case editor
    case typing
    case appearance
    case export
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @Binding var autoSaveEnabled: Bool
    @Binding var autoSaveInterval: Double
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("General")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Divider()
                    
                    // Auto-save
                    Toggle("Enable auto-save", isOn: $autoSaveEnabled)
                    
                    if autoSaveEnabled {
                        HStack {
                            Text("Auto-save interval:")
                            Spacer()
                            Slider(value: $autoSaveInterval, in: 10...120, step: 10)
                                .frame(width: 200)
                            Text("\(Int(autoSaveInterval))s")
                                .frame(width: 40, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                    }
                    
                    Divider()
                    
                    // Startup
                    VStack(alignment: .leading, spacing: 8) {
                        Text("On Startup")
                            .font(.headline)
                        
                        Picker("", selection: .constant("welcome")) {
                            Text("Show Welcome Screen").tag("welcome")
                            Text("Open Last Document").tag("last")
                            Text("Create New Document").tag("new")
                        }
                        .pickerStyle(.radioGroup)
                    }
                    
                    Divider()
                    
                    // File Management
                    VStack(alignment: .leading, spacing: 8) {
                        Text("File Management")
                            .font(.headline)
                        
                        Toggle("Keep backup copies", isOn: .constant(true))
                        Toggle("Restore open files on launch", isOn: .constant(true))
                        Toggle("Warn before closing unsaved documents", isOn: .constant(true))
                    }
                }
                .padding()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Editor Settings
struct EditorSettingsView: View {
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var fontFamily: String
    @Binding var showLineNumbers: Bool
    @Binding var highlightCurrentLine: Bool
    @Binding var indentSize: Int
    @Binding var useSpacesForTabs: Bool
    @Binding var copyImagesToDocumentFolder: Bool
    
    let availableFonts = ["SF Mono", "Menlo", "Monaco", "Courier New", "Source Code Pro", "Fira Code"]
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Editor")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Divider()
                    
                    // Font Settings
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Font")
                            .font(.headline)
                        
                        HStack {
                            Text("Font family:")
                            Spacer()
                            Picker("", selection: $fontFamily) {
                                ForEach(availableFonts, id: \.self) { font in
                                    Text(font).tag(font)
                                }
                            }
                            .frame(width: 200)
                        }
                        
                        HStack {
                            Text("Font size:")
                            Spacer()
                            Slider(value: $fontSize, in: 10...24, step: 1)
                                .frame(width: 200)
                            Text("\(Int(fontSize))pt")
                                .frame(width: 40, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Line height:")
                            Spacer()
                            Slider(value: $lineHeight, in: 1.0...2.5, step: 0.1)
                                .frame(width: 200)
                            Text(String(format: "%.1f", lineHeight))
                                .frame(width: 40, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    // Display
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display")
                            .font(.headline)
                        
                        Toggle("Show line numbers", isOn: $showLineNumbers)
                        Toggle("Highlight current line", isOn: $highlightCurrentLine)
                        Toggle("Show invisible characters", isOn: .constant(false))
                    }
                    
                    Divider()
                    
                    // Indentation
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Indentation")
                            .font(.headline)
                        
                        Toggle("Use spaces for tabs", isOn: $useSpacesForTabs)
                        
                        HStack {
                            Text("Indent size:")
                            Spacer()
                            Stepper("\(indentSize) spaces", value: $indentSize, in: 2...8)
                                .frame(width: 150)
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Images")
                            .font(.headline)
                        
                        Toggle("Copy images to document folder", isOn: $copyImagesToDocumentFolder)
                        Text("Optionally copy images next to the .md file for portability.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Typing Settings
struct TypingSettingsView: View {
    @Binding var spellCheckEnabled: Bool
    @Binding var grammarCheckEnabled: Bool
    @Binding var autoCapitalizationEnabled: Bool
    @Binding var smartQuotesEnabled: Bool
    @Binding var smartDashesEnabled: Bool
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Typing")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Divider()
                    
                    // Spell Checking
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Spell Checking")
                            .font(.headline)
                        
                        Toggle("Check spelling while typing", isOn: $spellCheckEnabled)
                        Toggle("Check grammar with spelling", isOn: $grammarCheckEnabled)
                            .disabled(!spellCheckEnabled)
                    }
                    
                    Divider()
                    
                    // Auto-correction
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Auto-correction")
                            .font(.headline)
                        
                        Toggle("Capitalize words automatically", isOn: $autoCapitalizationEnabled)
                        Toggle("Use smart quotes and dashes", isOn: $smartQuotesEnabled)
                        Toggle("Use smart dashes", isOn: $smartDashesEnabled)
                    }
                    
                    Divider()
                    
                    // Markdown
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Markdown")
                            .font(.headline)
                        
                        Toggle("Auto-pair brackets", isOn: .constant(true))
                        Toggle("Auto-pair quotes", isOn: .constant(true))
                        Toggle("Auto-close markdown syntax", isOn: .constant(true))
                        Toggle("Smart paste for URLs", isOn: .constant(true))
                    }
                    
                    Divider()
                    
                    // Behavior
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Behavior")
                            .font(.headline)
                        
                        Toggle("Trim trailing whitespace", isOn: .constant(true))
                        Toggle("Insert final newline", isOn: .constant(true))
                    }
                }
                .padding()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance Settings
struct AppearanceSettingsView: View {
    @ObservedObject private var themeService = ThemeService.shared
    @Binding var previewSyncScroll: Bool

    @AppStorage(AppConstants.Keys.showCodeLineNumbers) private var showCodeLineNumbers: Bool = false
    @AppStorage(AppConstants.Keys.focusDimInactiveLines) private var focusDimInactiveLines: Bool = false
    @AppStorage(AppConstants.Keys.focusHideSidebar) private var focusHideSidebar: Bool = true
    @AppStorage(AppConstants.Keys.focusHideOutline) private var focusHideOutline: Bool = true

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Appearance")
                        .font(.title2)
                        .fontWeight(.bold)

                    Divider()

                    ThemePickerView(themeService: themeService)

                    Toggle("Follow system light/dark appearance", isOn: Binding(
                        get: { themeService.followSystemAppearance },
                        set: { themeService.setFollowSystemAppearance($0) }
                    ))

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Preview")
                            .font(.headline)

                        Toggle("Sync scroll between editor and preview", isOn: $previewSyncScroll)
                            .onChange(of: previewSyncScroll) { _, enabled in
                                NotificationCenter.default.post(
                                    name: .editorExecJS,
                                    object: "window.cmEditor?.setSyncScroll(\(enabled));"
                                )
                            }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Code Blocks")
                            .font(.headline)

                        Toggle("Match code blocks to editor theme", isOn: Binding(
                            get: { themeService.isCodeThemeAutomatic },
                            set: { automatic in
                                if automatic {
                                    themeService.selectCodeTheme(
                                        themeService.themeFamily.pairedCodeTheme(isDark: themeService.isDarkMode),
                                        automatic: true
                                    )
                                } else {
                                    themeService.selectCodeTheme(themeService.currentCodeTheme, automatic: false)
                                }
                            }
                        ))

                        HStack {
                            Text("Syntax highlighting:")
                            Spacer()
                            Picker("", selection: Binding(
                                get: { themeService.currentCodeTheme },
                                set: { themeService.selectCodeTheme($0, automatic: false) }
                            )) {
                                ForEach(CodeTheme.allCases) { theme in
                                    Text(theme.displayName).tag(theme)
                                }
                            }
                            .frame(width: 200)
                            .disabled(themeService.isCodeThemeAutomatic)
                        }

                        if themeService.isCodeThemeAutomatic {
                            Text("Using \(themeService.currentCodeTheme.displayName) — paired with \(themeService.themeFamily.displayName).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Toggle("Show line numbers in code blocks", isOn: $showCodeLineNumbers)
                            .onChange(of: showCodeLineNumbers) { _, _ in
                                EditorAppearanceSync.pushLineNumbers()
                            }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Focus Mode")
                            .font(.headline)

                        Toggle("Dim editor chrome in focus mode", isOn: $focusDimInactiveLines)
                            .onChange(of: focusDimInactiveLines) { _, _ in
                                EditorAppearanceSync.pushFocusMode()
                            }

                        Toggle("Hide left sidebar in focus mode", isOn: $focusHideSidebar)
                            .onChange(of: focusHideSidebar) { _, _ in
                                NotificationCenter.default.post(name: .readingChromeSettingsChanged, object: nil)
                            }

                        Toggle("Hide outline panel in focus mode", isOn: $focusHideOutline)
                            .onChange(of: focusHideOutline) { _, _ in
                                NotificationCenter.default.post(name: .readingChromeSettingsChanged, object: nil)
                            }

                        Text("Applies in Preview (eye) and Focus Mode (⇧⌘F). Panels follow these defaults each time you enter; you can still toggle them while viewing. The formatting toolbar is always hidden in both modes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Export Settings
struct ExportSettingsView: View {
    @Binding var imageFormat: String
    @Binding var pdfMargins: Double
    @Binding var copyImagesToDocumentFolder: Bool
    @AppStorage(AppConstants.Keys.usePandocForDocxExport) private var usePandocForDocxExport = false
    
    let imageFormats = ["PNG", "JPEG", "SVG", "WebP"]
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Word (.docx)")
                            .font(.headline)

                        Text("Beardy2 uses a built-in exporter with embedded images, tables, lists, OMML math, and prerendered Mermaid diagrams.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Use Pandoc for DOCX when installed", isOn: $usePandocForDocxExport)
                            .help("Optional. Requires Pandoc (brew install pandoc). Off by default.")
                    }

                    Divider()
                    
                    // PDF Export
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PDF Export")
                            .font(.headline)
                        
                        HStack {
                            Text("Page margins:")
                            Spacer()
                            Slider(value: $pdfMargins, in: 36...144, step: 18)
                                .frame(width: 200)
                            Text("\(Int(pdfMargins))pt")
                                .frame(width: 50, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Paper size:")
                            Spacer()
                            Picker("", selection: .constant("letter")) {
                                Text("Letter").tag("letter")
                                Text("A4").tag("a4")
                                Text("Legal").tag("legal")
                            }
                            .frame(width: 150)
                        }
                        
                        Toggle("Include page numbers", isOn: .constant(true))
                        Toggle("Include table of contents", isOn: .constant(false))
                    }
                    
                    Divider()
                    
                    // HTML Export
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HTML Export")
                            .font(.headline)
                        
                        Toggle("Include CSS styles", isOn: .constant(true))
                        Toggle("Embed images beside document", isOn: $copyImagesToDocumentFolder)
                        Toggle("Generate standalone HTML", isOn: .constant(true))
                    }
                    
                    Divider()
                    
                    // Image Export
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Image Export")
                            .font(.headline)
                        
                        HStack {
                            Text("Default format:")
                            Spacer()
                            Picker("", selection: $imageFormat) {
                                ForEach(imageFormats, id: \.self) { format in
                                    Text(format).tag(format.lowercased())
                                }
                            }
                            .frame(width: 150)
                        }
                        
                        HStack {
                            Text("Image quality:")
                            Spacer()
                            Slider(value: .constant(90), in: 50...100, step: 5)
                                .frame(width: 200)
                            Text("90%")
                                .frame(width: 50, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                        
                        Toggle("Copy images to export folder", isOn: .constant(true))
                    }
                    
                    Divider()
                    
                    // Advanced
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Advanced")
                            .font(.headline)
                        
                        Toggle("Remove YAML frontmatter on export", isOn: .constant(false))
                        Toggle("Preserve empty lines", isOn: .constant(true))
                    }
                }
                .padding()
            }
        }
        .formStyle(.grouped)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(DocumentManager())
            .environmentObject(ThemeService.shared)
    }
}
