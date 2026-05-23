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
    @AppStorage(AppConstants.Keys.sidebarPanelWidth) private var sidebarPanelWidth: Double = AppConstants.Defaults.sidebarWidth
    @AppStorage(AppConstants.Keys.outlinePanelWidth) private var outlinePanelWidth: Double = AppConstants.Defaults.outlineWidth
    @State private var sidebarWidthDuringDrag: CGFloat?
    @State private var outlineWidthDuringDrag: CGFloat?
    @State private var selectedSidebarItem: SidebarItem? = .recentFiles
    @State private var editorScrollPosition: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let windowWidth = geometry.size.width
            let layout = panelLayout(for: windowWidth)

            HStack(spacing: 0) {
                if documentManager.showSidebar {
                    HStack(spacing: 0) {
                        SidebarView(selectedItem: $selectedSidebarItem)
                            .frame(width: layout.sidebarWidth)
                            .frame(maxHeight: .infinity)
                            .clipped()

                        PanelResizeHandle(
                            width: layout.sidebarWidth,
                            windowWidth: windowWidth,
                            sidebarVisible: documentManager.showSidebar,
                            outlineVisible: documentManager.showOutline,
                            sidebarPreferred: sidebarWidthDuringDrag ?? CGFloat(sidebarPanelWidth),
                            outlinePreferred: outlineWidthDuringDrag ?? CGFloat(outlinePanelWidth),
                            edge: .leadingPanel,
                            onWidthChange: { sidebarWidthDuringDrag = $0 },
                            onDragEnded: {
                                let width = sidebarWidthDuringDrag ?? layout.sidebarWidth
                                sidebarPanelWidth = Double(
                                    PanelWidthConstraints.sanitizedStoredWidth(
                                        width,
                                        defaultWidth: AppConstants.Defaults.sidebarWidth
                                    )
                                )
                                sidebarWidthDuringDrag = nil
                            }
                        )
                        .environmentObject(themeService)
                    }
                    .transition(PanelLayoutAnimation.leadingPanel)
                }

                mainEditorColumn(windowWidth: windowWidth, layout: layout)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(PanelLayoutAnimation.slide, value: documentManager.showSidebar)
            .animation(PanelLayoutAnimation.slide, value: documentManager.showOutline)
            .frame(width: windowWidth, height: geometry.size.height)
            .onAppear {
                repairStoredPanelWidthsIfNeeded()
                clampStoredWidthsForWindowResize(windowWidth)
            }
            .onChange(of: windowWidth) { _, newWidth in
                clampStoredWidthsForWindowResize(newWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: {
                    withAnimation(PanelLayoutAnimation.slide) {
                        documentManager.showSidebar.toggle()
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
                            .lineLimit(1)
                            .truncationMode(.tail)

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
                HStack {
                    ViewModeSegmentedPicker(selection: $documentManager.viewMode)
                    Divider()
                        .frame(height: 18)
                }

                HStack {
                    Button(action: {
                        themeService.toggleDarkMode()
                    }) {
                        Image(systemName: themeService.isDarkMode ? "moon.fill" : "sun.max.fill")
                    }
                    .help("Toggle Theme")
                    
                    if let doc = documentManager.currentDocument, doc.url != nil {
                        Button(action: {
                            documentManager.toggleFavoriteForActiveDocument()
                        }) {
                            Image(systemName: documentManager.isFavorite(path: doc.url!.path) ? "star.fill" : "star")
                        }
                        .help("Add to favorites")
                    }
                    
                    ShowShortcutsButton()
                    Button(action: {
                        openWindow(id: "custom_settings")
                    }) {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                    
                    Divider()
                        .frame(height: 18)
                }
            }
           

        }
        .onAppear {
            documentManager.syncReadingChromePanels()
        }
        .onChange(of: documentManager.sidebarToggleSignal) { _, _ in
            withAnimation(PanelLayoutAnimation.slide) {
                documentManager.showSidebar.toggle()
            }
        }
        .onChange(of: documentManager.focusMode) { _, _ in
            withAnimation(PanelLayoutAnimation.slide) {
                documentManager.syncReadingChromePanels()
            }
            EditorAppearanceSync.pushFocusMode()
        }
        .onChange(of: documentManager.viewMode) { _, _ in
            withAnimation(PanelLayoutAnimation.slide) {
                documentManager.syncReadingChromePanels()
            }
            EditorAppearanceSync.pushFocusMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readingChromeSettingsChanged)) { _ in
            withAnimation(PanelLayoutAnimation.slide) {
                documentManager.applyReadingChromePanelDefaultsIfActive()
            }
        }
    }

    private func panelLayout(for windowWidth: CGFloat) -> PanelLayoutMetrics {
        PanelWidthConstraints.resolve(
            windowWidth: windowWidth,
            sidebarVisible: documentManager.showSidebar,
            outlineVisible: documentManager.showOutline,
            sidebarPreferred: sidebarWidthDuringDrag ?? CGFloat(sidebarPanelWidth),
            outlinePreferred: outlineWidthDuringDrag ?? CGFloat(outlinePanelWidth)
        )
    }

    /// Fixes widths corrupted when panels were hidden (e.g. saved as 0).
    private func repairStoredPanelWidthsIfNeeded() {
        let sidebar = PanelWidthConstraints.sanitizedStoredWidth(
            CGFloat(sidebarPanelWidth),
            defaultWidth: AppConstants.Defaults.sidebarWidth
        )
        let outline = PanelWidthConstraints.sanitizedStoredWidth(
            CGFloat(outlinePanelWidth),
            defaultWidth: AppConstants.Defaults.outlineWidth
        )
        if sidebar != CGFloat(sidebarPanelWidth) {
            sidebarPanelWidth = Double(sidebar)
        }
        if outline != CGFloat(outlinePanelWidth) {
            outlinePanelWidth = Double(outline)
        }
    }

    private func clampStoredWidthsForWindowResize(_ windowWidth: CGFloat) {
        guard sidebarWidthDuringDrag == nil, outlineWidthDuringDrag == nil else { return }
        var sidebar = sidebarPanelWidth
        var outline = outlinePanelWidth
        PanelWidthConstraints.clampStored(
            sidebar: &sidebar,
            outline: &outline,
            windowWidth: windowWidth,
            sidebarVisible: documentManager.showSidebar,
            outlineVisible: documentManager.showOutline
        )
        sidebarPanelWidth = sidebar
        outlinePanelWidth = outline
    }

    @ViewBuilder
    private func mainEditorColumn(windowWidth: CGFloat, layout: PanelLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            if documentManager.hasOpenTabs {
                if !documentManager.isReadingChromeActive {
                    EditorToolbar()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(themeService.currentTheme.colors.code)

                    ThemedDivider()
                }

                DocumentTabBar()
                    .layoutPriority(0)

                ThemedDivider()

                EditorView(
                    scrollPosition: $editorScrollPosition,
                    windowWidth: windowWidth,
                    resolvedOutlineWidth: layout.outlineWidth,
                    outlineWidthDuringDrag: $outlineWidthDuringDrag,
                    onOutlineDragEnded: { width in
                        outlinePanelWidth = Double(
                            PanelWidthConstraints.sanitizedStoredWidth(
                                width,
                                defaultWidth: AppConstants.Defaults.outlineWidth
                            )
                        )
                        outlineWidthDuringDrag = nil
                    }
                )
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            } else {
                WelcomeView()
            }
        }
        .animation(nil, value: themeService.appearanceToken)
        .animation(nil, value: documentManager.viewMode)
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
