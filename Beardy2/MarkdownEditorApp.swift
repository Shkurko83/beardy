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
        // Инициализируем keyboard shortcuts manager
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
                
                Divider()
                
                Button("Export as PDF...") {
                    documentManager.exportAsPDF()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(documentManager.currentDocument == nil)
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
        }
        Window("Settings", id: "custom_settings") {
            SettingsView()
                .environmentObject(documentManager)
                .environmentObject(themeService)
        }
        .windowResizability(.contentSize)
    }
}
