//
//  Beardy2App.swift
//  Beardy2
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
        UserDefaults.standard.register(defaults: [
            AppConstants.Keys.focusHideSidebar: true,
            AppConstants.Keys.focusHideOutline: true,
        ])
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
                Button("Toggle Sidebar") {
                    documentManager.toggleSidebar()
                }
                .keyboardShortcut("\\", modifiers: .command)
                
                Button("Toggle Source Code Mode") {
                    documentManager.toggleSourceMode()
                }
                .keyboardShortcut("/", modifiers: .command)
                
                Button("Live Preview Mode") {
                    documentManager.viewMode = .live
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Focus Mode") {
                    documentManager.toggleFocusMode()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                
                Button("Typewriter Mode") {
                    documentManager.toggleTypewriterMode()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
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
    }
}
