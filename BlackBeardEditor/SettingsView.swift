//
//  SettingsView.swift
//  BlackBeardEditor
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
    @AppStorage(AppConstants.Keys.spellCheckEnabled) private var spellCheckEnabled: Bool = true
    @AppStorage(AppConstants.Keys.grammarCheckEnabled) private var grammarCheckEnabled: Bool = true
    @AppStorage(AppConstants.Keys.autoCapitalizationEnabled) private var autoCapitalizationEnabled: Bool = false
    @AppStorage(AppConstants.Keys.typographicPunctuationEnabled) private var typographicPunctuationEnabled: Bool = false
    @AppStorage(AppConstants.Keys.trimTrailingWhitespaceOnSave) private var trimTrailingWhitespaceOnSave: Bool = true
    @AppStorage(AppConstants.Keys.insertFinalNewlineOnSave) private var insertFinalNewlineOnSave: Bool = true
    @AppStorage(AppConstants.Keys.continueListsOnEnter) private var continueListsOnEnter: Bool = true
    @AppStorage(AppConstants.Keys.continueBlockquoteOnEnter) private var continueBlockquoteOnEnter: Bool = true
    @AppStorage(AppConstants.Keys.smartPasteURLs) private var smartPasteURLs: Bool = true
    @AppStorage(AppConstants.Keys.autoPairBrackets) private var autoPairBrackets: Bool = true
    @AppStorage(AppConstants.Keys.autoPairQuotes) private var autoPairQuotes: Bool = true
    @AppStorage(AppConstants.Keys.autoCloseMarkdown) private var autoCloseMarkdown: Bool = true
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = false
    @AppStorage("highlightCurrentLine") private var highlightCurrentLine: Bool = true
    @AppStorage("indentSize") private var indentSize: Int = 4
    @AppStorage("useSpacesForTabs") private var useSpacesForTabs: Bool = true
    @AppStorage(AppConstants.Keys.previewSyncScroll) private var previewSyncScroll: Bool = true
    @AppStorage(ImageInsertionHelper.copyImagesToDocumentFolderKey) private var copyImagesToDocumentFolder: Bool = true
    @AppStorage(AppConstants.Keys.startupAction) private var startupAction: String = AppConstants.StartupAction.welcome.rawValue
    @AppStorage(AppConstants.Keys.recoveryBackupEnabled) private var recoveryBackupEnabled: Bool = true
    @AppStorage(AppConstants.Keys.restoreOpenFilesOnLaunch) private var restoreOpenFilesOnLaunch: Bool = true
    @AppStorage(AppConstants.Keys.warnBeforeClosingUnsaved) private var warnBeforeClosingUnsaved: Bool = true
    
    @State private var selectedTab: SettingsTab = .general
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(
                autoSaveEnabled: $autoSaveEnabled,
                autoSaveInterval: $autoSaveInterval,
                startupAction: $startupAction,
                recoveryBackupEnabled: $recoveryBackupEnabled,
                restoreOpenFilesOnLaunch: $restoreOpenFilesOnLaunch,
                warnBeforeClosingUnsaved: $warnBeforeClosingUnsaved
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
                typographicPunctuationEnabled: $typographicPunctuationEnabled,
                trimTrailingWhitespaceOnSave: $trimTrailingWhitespaceOnSave,
                insertFinalNewlineOnSave: $insertFinalNewlineOnSave,
                continueListsOnEnter: $continueListsOnEnter,
                continueBlockquoteOnEnter: $continueBlockquoteOnEnter,
                smartPasteURLs: $smartPasteURLs,
                autoPairBrackets: $autoPairBrackets,
                autoPairQuotes: $autoPairQuotes,
                autoCloseMarkdown: $autoCloseMarkdown
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
            
            ExportSettingsView()
            .tabItem {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .tag(SettingsTab.export)
        }
        .frame(width: 600, height: 580)
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
    @Binding var startupAction: String
    @Binding var recoveryBackupEnabled: Bool
    @Binding var restoreOpenFilesOnLaunch: Bool
    @Binding var warnBeforeClosingUnsaved: Bool
    
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
                        
                        Picker("", selection: $startupAction) {
                            ForEach(AppConstants.StartupAction.allCases) { action in
                                Text(action.label).tag(action.rawValue)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                    
                    Divider()
                    
                    // File Management
                    VStack(alignment: .leading, spacing: 8) {
                        Text("File Management")
                            .font(.headline)
                        
                        Toggle("Keep recovery copy until saved", isOn: $recoveryBackupEnabled)
                            .help("Stores unsaved edits in Application Support until you save. Offers recovery after an unexpected quit.")
                        Toggle("Restore open files on launch", isOn: $restoreOpenFilesOnLaunch)
                            .help("Reopens tabs from your last session when On Startup is “Open Last Document”. Ignored for Welcome Screen and Create New Document.")
                        Toggle("Warn before closing unsaved documents", isOn: $warnBeforeClosingUnsaved)
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
                            .onChange(of: fontFamily) { _, _ in EditorSettingsSync.pushToEditor() }
                        }
                        
                        HStack {
                            Text("Font size:")
                            Spacer()
                            Slider(value: $fontSize, in: 10...24, step: 1)
                                .frame(width: 200)
                                .onChange(of: fontSize) { _, _ in EditorSettingsSync.pushToEditor() }
                            Text("\(Int(fontSize))pt")
                                .frame(width: 40, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Line height:")
                            Spacer()
                            Slider(value: $lineHeight, in: 1.0...2.5, step: 0.1)
                                .frame(width: 200)
                                .onChange(of: lineHeight) { _, _ in EditorSettingsSync.pushToEditor() }
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
                            .onChange(of: showLineNumbers) { _, enabled in
                                if !enabled {
                                    highlightCurrentLine = false
                                }
                                EditorSettingsSync.pushToEditor()
                            }
                        Toggle("Highlight current line", isOn: $highlightCurrentLine)
                            .disabled(!showLineNumbers)
                            .onChange(of: highlightCurrentLine) { _, _ in EditorSettingsSync.pushToEditor() }
                    }
                    
                    Divider()
                    
                    // Indentation
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Indentation")
                            .font(.headline)
                        
                        Toggle("Use spaces for tabs", isOn: $useSpacesForTabs)
                            .onChange(of: useSpacesForTabs) { _, _ in EditorSettingsSync.pushToEditor() }

                        HStack {
                            Text("Indent size:")
                            Spacer()
                            Stepper("\(indentSize) spaces", value: $indentSize, in: 2...8)
                                .frame(width: 150)
                                .onChange(of: indentSize) { _, _ in EditorSettingsSync.pushToEditor() }
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
    @Binding var typographicPunctuationEnabled: Bool
    @Binding var trimTrailingWhitespaceOnSave: Bool
    @Binding var insertFinalNewlineOnSave: Bool
    @Binding var continueListsOnEnter: Bool
    @Binding var continueBlockquoteOnEnter: Bool
    @Binding var smartPasteURLs: Bool
    @Binding var autoPairBrackets: Bool
    @Binding var autoPairQuotes: Bool
    @Binding var autoCloseMarkdown: Bool

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Typing")
                        .font(.title2)
                        .fontWeight(.bold)

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Spell Checking")
                            .font(.headline)

                        TypingSettingRow(
                            title: "Check spelling while typing",
                            caption: "Underlines misspelled words as you type.",
                            isOn: $spellCheckEnabled
                        )
                        .onChange(of: spellCheckEnabled) { _, enabled in
                            if !enabled {
                                grammarCheckEnabled = false
                            }
                            TypingSettingsSync.pushToEditor()
                        }

                        TypingSettingRow(
                            title: "Check grammar with spelling",
                            caption: "Adds grammar hints when macOS provides them.",
                            isOn: $grammarCheckEnabled,
                            disabled: !spellCheckEnabled
                        )
                        .onChange(of: grammarCheckEnabled) { _, _ in
                            TypingSettingsSync.pushToEditor()
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Auto-correction")
                            .font(.headline)

                        TypingSettingRow(
                            title: "Capitalize sentences automatically",
                            caption: "Capitalizes the first letter after a sentence end.",
                            isOn: $autoCapitalizationEnabled
                        )
                        .onChange(of: autoCapitalizationEnabled) { _, _ in
                            TypingSettingsSync.pushToEditor()
                        }

                        TypingSettingRow(
                            title: "Typographic punctuation",
                            caption: "Curly quotes and em dashes instead of straight ASCII.",
                            isOn: $typographicPunctuationEnabled
                        )
                        .onChange(of: typographicPunctuationEnabled) { _, _ in
                            TypingSettingsSync.pushToEditor()
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("On Save")
                            .font(.headline)

                        TypingSettingRow(
                            title: "Trim trailing whitespace",
                            caption: "Removes spaces at the end of each line when saving.",
                            isOn: $trimTrailingWhitespaceOnSave
                        )

                        TypingSettingRow(
                            title: "Insert final newline",
                            caption: "Ensures the file ends with a single newline when saving.",
                            isOn: $insertFinalNewlineOnSave
                        )
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Markdown")
                            .font(.headline)

                        TypingSettingRow(
                            title: "Continue lists on Enter",
                            caption: "Repeats the list marker on the next line; empty item ends the list.",
                            isOn: $continueListsOnEnter
                        )
                        .onChange(of: continueListsOnEnter) { _, _ in
                            TypingSettingsSync.pushToEditor()
                        }

                        TypingSettingRow(
                            title: "Continue blockquote on Enter",
                            caption: "Inserts \"> \" on the next line; empty line exits the quote.",
                            isOn: $continueBlockquoteOnEnter
                        )
                        .onChange(of: continueBlockquoteOnEnter) { _, _ in
                            TypingSettingsSync.pushToEditor()
                        }

                        TypingSettingRow(
                            title: "Smart paste URLs",
                            caption: "Turns pasted links into Markdown links, using selected text as the label.",
                            isOn: $smartPasteURLs
                        )
                        .onChange(of: smartPasteURLs) { _, _ in
                            TypingSettingsSync.pushToEditor()
                        }

                        TypingSettingRow(
                            title: "Auto-pair brackets",
                            caption: "Inserts closing ), ], or } and skips over it when typed again.",
                            isOn: $autoPairBrackets
                        )
                        .onChange(of: autoPairBrackets) { _, _ in
                            TypingSettingsSync.pushToEditor()
                        }

                        TypingSettingRow(
                            title: "Auto-pair quotes and backticks",
                            caption: "Pairs \", ', and ` for inline code; skipped when typographic quotes are on.",
                            isOn: $autoPairQuotes
                        )
                        .onChange(of: autoPairQuotes) { _, _ in
                            TypingSettingsSync.pushToEditor()
                        }

                        TypingSettingRow(
                            title: "Auto-close bold and strikethrough",
                            caption: "Typing * or ~ inserts ** or ~~ with the cursor inside.",
                            isOn: $autoCloseMarkdown
                        )
                        .onChange(of: autoCloseMarkdown) { _, _ in
                            TypingSettingsSync.pushToEditor()
                        }
                    }
                }
                .padding()
            }
        }
        .formStyle(.grouped)
    }
}

private struct TypingSettingRow: View {
    let title: String
    let caption: String
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn)
                .disabled(disabled)
            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
    @AppStorage(AppConstants.Keys.usePandocForDocxExport) private var usePandocForDocxExport = false
    @AppStorage(AppConstants.Keys.exportPDFMarginTop) private var marginTop: Double = 72
    @AppStorage(AppConstants.Keys.exportPDFMarginBottom) private var marginBottom: Double = 72
    @AppStorage(AppConstants.Keys.exportPDFMarginLeft) private var marginLeft: Double = 72
    @AppStorage(AppConstants.Keys.exportPDFMarginRight) private var marginRight: Double = 72
    @AppStorage(AppConstants.Keys.exportPDFPaperSize) private var paperSize: String = "letter"
    @AppStorage(AppConstants.Keys.exportPDFIncludePageNumbers) private var includePageNumbers = false
    @AppStorage(AppConstants.Keys.exportPDFIncludeTOC) private var includeTOC = false
    @AppStorage(AppConstants.Keys.exportPDFIncludeThemeBackground) private var includeThemeBackground = false
    @AppStorage(AppConstants.Keys.exportHTMLStandalone) private var htmlStandalone = true
    @AppStorage(AppConstants.Keys.exportRemoveYAMLFrontmatter) private var removeYAMLFrontmatter = false
    @AppStorage(AppConstants.Keys.exportPreserveEmptyLines) private var preserveEmptyLines = true

    var body: some View {
        Form {
            Section {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Export")
                            .font(.title2)
                            .fontWeight(.bold)

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Word (.docx)")
                                .font(.headline)

                            settingCaption("Black Beard Editor uses a built-in exporter with embedded images, tables, lists, OMML math, and prerendered Mermaid diagrams.")

                            Toggle("Use Pandoc for DOCX when installed", isOn: $usePandocForDocxExport)
                            settingCaption("When enabled and Pandoc is available, Word export uses Pandoc instead of the built-in writer. Requires Pandoc (brew install pandoc).")
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("PDF Export")
                                .font(.headline)

                            settingCaption("Page margins in points (72 pt = 1 inch). Content stays inside these margins.")

                            marginRow("Top", value: $marginTop)
                            marginRow("Bottom", value: $marginBottom)
                            marginRow("Left", value: $marginLeft)
                            marginRow("Right", value: $marginRight)

                            Button("Reset margins to 72 pt") {
                                marginTop = 72
                                marginBottom = 72
                                marginLeft = 72
                                marginRight = 72
                            }
                            .buttonStyle(.link)

                            HStack {
                                Text("Paper size")
                                Spacer()
                                Picker("", selection: $paperSize) {
                                    Text("Letter").tag("letter")
                                    Text("A4").tag("a4")
                                    Text("Legal").tag("legal")
                                }
                                .labelsHidden()
                                .frame(width: 150)
                            }
                            settingCaption("Physical page size used when saving a PDF.")

                            Toggle("Include page numbers", isOn: $includePageNumbers)
                            settingCaption("Adds centered page numbers in the bottom margin of each page.")

                            Toggle("Include table of contents", isOn: $includeTOC)
                            settingCaption("Inserts a linked table of contents from document headings at the start of the PDF.")

                            Toggle("Use editor theme", isOn: $includeThemeBackground)
                            settingCaption("You get the PDF exactly as you see it on the screen.")
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("HTML Export")
                                .font(.headline)

                            settingCaption("Styled vs plain HTML is chosen from the Export menu (HTML vs HTML without styles).")

                            Toggle("Standalone HTML file", isOn: $htmlStandalone)
                            settingCaption("When on, images are embedded in the HTML file. When off, images are copied into a sibling folder and linked with relative paths.")
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Advanced")
                                .font(.headline)

                            Toggle("Remove YAML frontmatter on export", isOn: $removeYAMLFrontmatter)
                            settingCaption("Strips a leading --- … --- metadata block before exporting to any format.")

                            Toggle("Preserve empty lines", isOn: $preserveEmptyLines)
                            settingCaption("Keeps blank lines in plain text export. HTML and PDF always use normal Markdown blank-line rules so structure matches preview.")
                        }
                    }
                    .padding()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func marginRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .frame(width: 56, alignment: .leading)
            Slider(value: value, in: 18...144, step: 6)
            Text("\(Int(value.wrappedValue)) pt")
                .frame(width: 52, alignment: .trailing)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    private func settingCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(DocumentManager())
            .environmentObject(ThemeService.shared)
    }
}
