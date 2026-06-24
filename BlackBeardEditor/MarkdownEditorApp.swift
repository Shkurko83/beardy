//
//  MarkdownEditorApp.swift
//  BlackBeardEditor
//
//  Created by Butt Simpson on 27.12.2025.
//

import SwiftUI

@main
struct MarkdownEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var documentManager = DocumentManager()
    @StateObject private var themeService = ThemeService.shared
    
    init() {
        TypingSettingsSync.migrateLegacySettingsIfNeeded()
        UserDefaults.standard.register(defaults: [
            AppConstants.Keys.webContinuousSpellChecking: true,
            AppConstants.Keys.focusHideSidebar: true,
            AppConstants.Keys.focusHideOutline: true,
            AppConstants.Keys.previewSyncScroll: true,
            AppConstants.Keys.startupAction: AppConstants.StartupAction.welcome.rawValue,
            AppConstants.Keys.recoveryBackupEnabled: true,
            AppConstants.Keys.restoreOpenFilesOnLaunch: true,
            AppConstants.Keys.warnBeforeClosingUnsaved: true,
            AppConstants.Keys.autoSaveEnabled: true,
            AppConstants.Keys.autoSaveInterval: 30,
            AppConstants.Keys.editorFontSize: AppConstants.Defaults.fontSize,
            AppConstants.Keys.editorLineHeight: AppConstants.Defaults.lineHeight,
            AppConstants.Keys.editorFontFamily: AppConstants.Defaults.fontFamily,
            AppConstants.Keys.showLineNumbers: false,
            AppConstants.Keys.highlightCurrentLine: true,
            AppConstants.Keys.indentSize: AppConstants.Defaults.tabSize,
            AppConstants.Keys.useSpacesForTabs: true,
            AppConstants.Keys.spellCheckEnabled: true,
            AppConstants.Keys.grammarCheckEnabled: true,
            AppConstants.Keys.autoCapitalizationEnabled: false,
            AppConstants.Keys.typographicPunctuationEnabled: false,
            AppConstants.Keys.trimTrailingWhitespaceOnSave: true,
            AppConstants.Keys.insertFinalNewlineOnSave: true,
            AppConstants.Keys.continueListsOnEnter: true,
            AppConstants.Keys.continueBlockquoteOnEnter: true,
            AppConstants.Keys.smartPasteURLs: true,
            AppConstants.Keys.autoPairBrackets: true,
            AppConstants.Keys.autoPairQuotes: true,
            AppConstants.Keys.autoCloseMarkdown: true,
            AppConstants.Keys.exportPDFMarginTop: 72,
            AppConstants.Keys.exportPDFMarginBottom: 72,
            AppConstants.Keys.exportPDFMarginLeft: 72,
            AppConstants.Keys.exportPDFMarginRight: 72,
            AppConstants.Keys.exportPDFPaperSize: "letter",
            AppConstants.Keys.exportPDFIncludePageNumbers: false,
            AppConstants.Keys.exportPDFIncludeTOC: false,
            AppConstants.Keys.exportPDFIncludeThemeBackground: false,
            AppConstants.Keys.exportHTMLStandalone: true,
            AppConstants.Keys.exportRemoveYAMLFrontmatter: false,
            AppConstants.Keys.exportPreserveEmptyLines: true,
            AppConstants.Keys.usePandocForDocxExport: false,
        ])
        SecurityBookmarkStore.performStartupMaintenance()
        _ = KeyboardShortcutsManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(documentManager)
                .environmentObject(themeService)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    DocumentManager.shared = documentManager
                }
        }
        .commands {
            // File menu commands
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    documentManager.createNewDocument()
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Open...") {
                    documentManager.openDocument()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Close Tab") {
                    if let id = documentManager.selectedTabID {
                        documentManager.closeTab(id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(documentManager.selectedTabID == nil)
            }
            
            CommandGroup(after: .newItem) {
                Button("Save") {
                    documentManager.saveDocument()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(documentManager.currentDocument == nil)
                
                Button("Save As...") {
                    documentManager.saveDocumentAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(documentManager.currentDocument == nil)
                
            }
            
            CommandMenu("Export") {
                Button("PDF...") {
                    documentManager.exportDocument(as: .pdf)
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(documentManager.currentDocument == nil)
                
                Divider()
                
                Button("HTML...") {
                    documentManager.exportDocument(as: .html)
                }
                .disabled(documentManager.currentDocument == nil)
                
                Button("HTML (without styles)...") {
                    documentManager.exportDocument(as: .htmlPlain)
                }
                .disabled(documentManager.currentDocument == nil)
                
                Divider()
                
                Button("Word (.docx)...") {
                    documentManager.exportDocument(as: .docx)
                }
                .disabled(documentManager.currentDocument == nil)
                
                Button("OpenDocument (.odt)...") {
                    documentManager.exportDocument(as: .odt)
                }
                .disabled(documentManager.currentDocument == nil)
                
                Button("RTF...") {
                    documentManager.exportDocument(as: .rtf)
                }
                .disabled(documentManager.currentDocument == nil)
                
                Button("EPUB...") {
                    documentManager.exportDocument(as: .epub)
                }
                .disabled(documentManager.currentDocument == nil || !PandocConverter.isAvailable)
                
                Button("LaTeX...") {
                    documentManager.exportDocument(as: .latex)
                }
                .disabled(documentManager.currentDocument == nil || !PandocConverter.isAvailable)
                
                Divider()
                
                Button("Plain Text...") {
                    documentManager.exportDocument(as: .plainText)
                }
                .disabled(documentManager.currentDocument == nil)
                
                Button("Markdown...") {
                    documentManager.exportDocument(as: .markdown)
                }
                .disabled(documentManager.currentDocument == nil)
            }
            
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    documentManager.requestUndo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!documentManager.canUndo)

                Button("Redo") {
                    documentManager.requestRedo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!documentManager.canRedo)
            }

            // Edit menu commands
            CommandGroup(after: .pasteboard) {
                Divider()
                
                Button("Find...") {
                    documentManager.showFindPanel()
                }
                .keyboardShortcut("f", modifiers: .command)
                
                Button("Replace...") {
                    documentManager.showReplacePanel()
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
            }
            
            // Format menu
            CommandMenu("Format") {
                Button("Bold") {
                    documentManager.toggleBold()
                }
                .keyboardShortcut("b", modifiers: .command)
                
                Button("Italic") {
                    documentManager.toggleItalic()
                }
                .keyboardShortcut("i", modifiers: .command)
                
                Button("Strikethrough") {
                    documentManager.toggleStrikethrough()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Inline Code") {
                    documentManager.toggleInlineCode()
                }
                .keyboardShortcut("`", modifiers: .command)
                
                Button("Code Block") {
                    documentManager.insertCodeBlock()
                }
                .keyboardShortcut("`", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Insert Link") {
                    documentManager.insertLink()
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Button("Insert Image") {
                    documentManager.insertImage()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Divider()
                
                Menu("Heading") {
                    ForEach(1...6, id: \.self) { level in
                        Button("Heading \(level)") {
                            documentManager.insertHeading(level: level)
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(level))), modifiers: .command)
                    }
                }
            }
            
            // View menu
            CommandMenu("View") {
                Toggle("Sidebar", isOn: $documentManager.showSidebar)
                    .keyboardShortcut("\\", modifiers: .command)

                Toggle("Outline", isOn: $documentManager.showOutline)
                    .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                ViewModeMenuCommands(documentManager: documentManager)
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(themeService)
        }
        Window("Settings", id: "custom_settings") {
            SettingsView()
                .environmentObject(themeService)
        }
        .windowResizability(.contentSize)

        Window("Find", id: "find_replace") {
            FindReplaceWindowView()
                .environmentObject(documentManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 200)
    }
}

// MARK: - View menu mode items (checkmarks match toolbar picker)

private struct ViewModeMenuCommands: View {
    @ObservedObject var documentManager: DocumentManager

    var body: some View {
        Group {
            modeButton(.edit, shortcut: "/", modifiers: .command)
            modeButton(.live, shortcut: "l", modifiers: [.command, .shift])
            modeButton(.preview, shortcut: "p", modifiers: [.command, .shift])
            modeButton(.split, shortcut: "s", modifiers: [.control, .command])
            modeButton(.diff, shortcut: "d", modifiers: [.command, .option])
        }
    }

    @ViewBuilder
    private func modeButton(
        _ mode: ViewMode,
        shortcut: KeyEquivalent,
        modifiers: EventModifiers
    ) -> some View {
        Button {
            documentManager.viewMode = mode
        } label: {
            HStack {
                Text(mode.rawValue)
                Spacer(minLength: 12)
                if documentManager.viewMode == mode {
                    Image(systemName: "checkmark")
                }
            }
        }
        .keyboardShortcut(shortcut, modifiers: modifiers)
    }
}
