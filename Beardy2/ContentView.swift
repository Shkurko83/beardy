//
//  ContentView.swift
//  Beardy2
//
//  Created by Butt Simpson on 27.12.2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var themeService: ThemeService
    @Environment(\.openWindow) private var openWindow
    @State private var showSidebar = true
    @State private var sidebarBeforeReadingChrome: Bool?
    @State private var wasReadingChrome = false
    @State private var sidebarWidth: CGFloat = 250
    @State private var selectedSidebarItem: SidebarItem? = .recentFiles
    @State private var editorScrollPosition: CGFloat = 0
    @AppStorage(AppConstants.Keys.focusHideSidebar) private var focusHideSidebar = true

    private var showsEditorToolbar: Bool {
        !documentManager.isReadingChromeMode
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(selectedItem: $selectedSidebarItem)
                    .frame(minWidth: 200, idealWidth: sidebarWidth, maxWidth: 400)

                ThemedDivider()
            }

            VStack(spacing: 0) {
                if documentManager.hasOpenTabs {
                    if showsEditorToolbar {
                        EditorToolbar()
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(themeService.currentTheme.colors.code)

                        ThemedDivider()
                    }

                    DocumentTabBar()
                        .layoutPriority(0)

                    ThemedDivider()

                    EditorView(scrollPosition: $editorScrollPosition)
                        .layoutPriority(1)
                } else {
                    WelcomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(nil, value: themeService.appearanceToken)
            .animation(nil, value: documentManager.viewMode)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: {
                    withAnimation {
                        showSidebar.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }
            
            ToolbarItemGroup(placement: .principal) {
                if let doc = documentManager.currentDocument {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.secondary)
                        
                        Text(doc.fileName)
                            .font(.headline)
                        
                        if doc.hasUnsavedChanges {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            ToolbarItemGroup(placement: .automatic) {
                if let doc = documentManager.currentDocument, doc.url != nil {
                    Button(action: {
                        documentManager.toggleFavoriteForActiveDocument()
                    }) {
                        Image(systemName: documentManager.isFavorite(path: doc.url!.path) ? "star.fill" : "star")
                    }
                    .help("Add to favorites")
                }

                ShowShortcutsButton()
                // View mode toggle
                Picker("", selection: $documentManager.viewMode) {
                    Label("Edit", systemImage: "pencil")
                        .tag(ViewMode.edit)
                    Label("Live", systemImage: "doc.richtext")
                        .tag(ViewMode.live)
                    Label("Preview", systemImage: "eye")
                        .tag(ViewMode.preview)
                    Label("Split", systemImage: "rectangle.split.2x1")
                        .tag(ViewMode.split)
                }
                .pickerStyle(.segmented)
                .help("View Mode")
                .animation(nil, value: documentManager.viewMode)


                // Theme toggle
                Button(action: {
                    themeService.toggleDarkMode()
                }) {
                    Image(systemName: themeService.isDarkMode ? "moon.fill" : "sun.max.fill")
                }
                .help("Toggle Theme")

                
                // Settings
                Button(action: {
                    openWindow(id: "custom_settings")
                }) {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .onAppear {
            documentManager.showSidebarBinding = $showSidebar
            wasReadingChrome = documentManager.isReadingChromeMode
            if wasReadingChrome {
                enterReadingChromeSidebar()
            }
        }
        .onChange(of: documentManager.sidebarToggleSignal) { _, _ in
            withAnimation {
                showSidebar.toggle()
            }
        }
        .onChange(of: documentManager.focusMode) { _, _ in
            handleReadingChromeSidebarTransition()
        }
        .onChange(of: documentManager.viewMode) { _, _ in
            handleReadingChromeSidebarTransition()
        }
        .onChange(of: focusHideSidebar) { _, _ in
            applyReadingChromeSidebarDefaultsIfActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readingChromeSettingsChanged)) { _ in
            applyReadingChromeSidebarDefaultsIfActive()
        }
    }

    private func handleReadingChromeSidebarTransition() {
        let active = documentManager.isReadingChromeMode
        if active && !wasReadingChrome {
            enterReadingChromeSidebar()
        } else if !active && wasReadingChrome {
            exitReadingChromeSidebar()
        }
        wasReadingChrome = active
    }

    /// Applies Appearance defaults when entering preview/focus. Manual toggles do not affect the next entry.
    private func enterReadingChromeSidebar() {
        if sidebarBeforeReadingChrome == nil {
            sidebarBeforeReadingChrome = showSidebar
        }
        withAnimation {
            showSidebar = !focusHideSidebar
        }
    }

    private func exitReadingChromeSidebar() {
        guard let saved = sidebarBeforeReadingChrome else { return }
        withAnimation {
            showSidebar = saved
        }
        sidebarBeforeReadingChrome = nil
    }

    private func applyReadingChromeSidebarDefaultsIfActive() {
        guard documentManager.isReadingChromeMode else { return }
        withAnimation {
            showSidebar = !focusHideSidebar
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case recentFiles = "Recent Files"
    case favorites = "Favorites"
    case folders = "Folders"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .recentFiles: return "clock"
        case .favorites: return "star"
        case .folders: return "folder"
        }
    }
}

enum ViewMode: String, CaseIterable {
    case edit = "Edit"
    case preview = "Preview"
    case split = "Split"
    case live = "Live"
}

private struct ThemedDivider: View {
    @EnvironmentObject private var themeService: ThemeService

    var body: some View {
        Divider()
            .overlay(themeService.currentTheme.colors.border)
    }
}
