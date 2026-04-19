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
    @State private var sidebarWidth: CGFloat = 250
    @State private var selectedSidebarItem: SidebarItem? = .recentFiles
    @State private var editorScrollPosition: CGFloat = 0
    
    var body: some View {
        NavigationView {
            // Sidebar
            if showSidebar {
                SidebarView(selectedItem: $selectedSidebarItem)
                    .frame(minWidth: 200, idealWidth: sidebarWidth, maxWidth: 400)
                    .layoutPriority(1)
            }
            
            // Main Editor Area
            ZStack {
                if documentManager.currentDocument == nil {
                    WelcomeView()
                } else {
                    EditorView(scrollPosition: $editorScrollPosition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationViewStyle(.automatic)
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
        }
        .onChange(of: documentManager.sidebarToggleSignal) { _, _ in
            withAnimation {
                showSidebar.toggle()
            }
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
