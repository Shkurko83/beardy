//
//  SidebarView.swift
//  Beardy2
//
//  Created by Butt Simpson on 27.12.2025.
//

import SwiftUI

struct SidebarView: View {
    @Binding var selectedItem: SidebarItem?
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var themeService: ThemeService
    @State private var recentFiles: [RecentDocument] = []
    @State private var favorites: [FavoriteDocument] = []
    @State private var folders: [FolderItem] = []
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                
                TextField("Search files...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            
            Divider()
            
            // Sidebar Navigation
            List(selection: $selectedItem) {
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        NavigationLink(value: item) {
                            Label(item.rawValue, systemImage: item.icon)
                                .font(.system(size: 13))
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            .listStyle(.sidebar)
            .frame(height: 120)
            
            Divider()
            
            // Content Area based on selection
            ScrollView {
                VStack(spacing: 0) {
                    if let selected = selectedItem {
                        switch selected {
                        case .recentFiles:
                            RecentFilesSection(files: filteredRecentFiles)
                        case .favorites:
                            FavoritesSection(favorites: filteredFavorites)
                        case .folders:
                            FoldersSection(folders: filteredFolders)
                        }
                    }
                }
            }
            
            Divider()
            
            // Bottom Action Buttons
            HStack(spacing: 12) {
                Button(action: {
                    documentManager.createNewDocument()
                }) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("New Document")
                
                Button(action: {
                    documentManager.openDocument()
                }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Open File")
                
                Spacer()
                
                Button(action: {
                    refreshSidebar()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .background(themeService.currentTheme.colors.background.opacity(0.5))
        .onAppear {
            loadSidebarData()
        }
    }
    
//    private var filteredRecentFiles: [RecentDocument] {
//        if searchText.isEmpty {
//            return recentFiles
//        }
//        return recentFiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
//    }
    
    private var filteredRecentFiles: [RecentDocument] {
        if searchText.isEmpty {
            return recentFiles
        }
        return recentFiles.filter { doc in
            // Поиск по имени и пути
            if doc.name.localizedCaseInsensitiveContains(searchText) ||
               doc.path.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            
            // Опционально: поиск в содержимом (медленнее)
            if let content = try? String(contentsOf: doc.url, encoding: .utf8) {
                return content.localizedCaseInsensitiveContains(searchText)
            }
            
            return false
        }
    }
    
    private var filteredFavorites: [FavoriteDocument] {
        if searchText.isEmpty {
            return favorites
        }
        return favorites.filter { doc in
            doc.name.localizedCaseInsensitiveContains(searchText) ||
            doc.path.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var filteredFolders: [FolderItem] {
        if searchText.isEmpty {
            return folders
        }
        return folders.filter { folder in
            folder.name.localizedCaseInsensitiveContains(searchText) ||
            folder.path.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func loadSidebarData() {
        recentFiles = documentManager.getRecentDocuments()
        favorites = documentManager.getFavorites()
        folders = documentManager.getFolders()
    }
    
    private func refreshSidebar() {
        loadSidebarData()
    }
}

// MARK: - Recent Files Section
struct RecentFilesSection: View {
    let files: [RecentDocument]
    @EnvironmentObject var documentManager: DocumentManager
    
    var body: some View {
        VStack(spacing: 0) {
            if files.isEmpty {
                EmptyStateView(
                    icon: "clock",
                    title: "No Recent Files",
                    message: "Your recently opened files will appear here"
                )
            } else {
                ForEach(files) { file in
                    SidebarFileRow(
                        icon: "doc.text",
                        name: file.name,
                        subtitle: file.path,
                        date: file.modifiedDate
                    ) {
                        documentManager.openRecentDocument(file)
                    } onFavorite: {
                        documentManager.toggleFavorite(file)
                    }
                }
            }
        }
    }
}

// MARK: - Favorites Section
struct FavoritesSection: View {
    let favorites: [FavoriteDocument]
    @EnvironmentObject var documentManager: DocumentManager
    
    var body: some View {
        VStack(spacing: 0) {
            if favorites.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "No Favorites",
                    message: "Star files to add them to favorites"
                )
            } else {
                ForEach(favorites) { favorite in
                    SidebarFileRow(
                        icon: "doc.text.fill",
                        name: favorite.name,
                        subtitle: favorite.path,
                        date: favorite.addedDate,
                        isFavorite: true
                    ) {
                        documentManager.openFavorite(favorite)
                    } onFavorite: {
                        documentManager.removeFavorite(favorite)
                    }
                }
            }
        }
    }
}

// MARK: - Folders Section
struct FoldersSection: View {
    let folders: [FolderItem]
    @EnvironmentObject var documentManager: DocumentManager
    @State private var expandedFolders: Set<UUID> = []
    
    var body: some View {
        VStack(spacing: 0) {
            if folders.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: "No Folders",
                    message: "Add folders to quick access"
                )
                
                Button("Add Folder") {
                    documentManager.addFolder()
                }
                .buttonStyle(.bordered)
                .padding(.top, 12)
            } else {
                ForEach(folders) { folder in
                    FolderRowView(
                        folder: folder,
                        isExpanded: expandedFolders.contains(folder.id)
                    ) {
                        toggleFolder(folder.id)
                    } onOpen: {
                        documentManager.openFolder(folder)
                    }
                }
            }
        }
    }
    
    private func toggleFolder(_ id: UUID) {
        if expandedFolders.contains(id) {
            expandedFolders.remove(id)
        } else {
            expandedFolders.insert(id)
        }
    }
}

// MARK: - Sidebar File Row
struct SidebarFileRow: View {
    let icon: String
    let name: String
    let subtitle: String
    let date: Date
    var isFavorite: Bool = false
    let onTap: () -> Void
    let onFavorite: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isHovered {
                    Button(action: onFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundColor(isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Folder Row View
struct FolderRowView: View {
    let folder: FolderItem
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    
                    Text(folder.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(folder.fileCount)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            
            if isExpanded {
                ForEach(folder.files) { file in
                    HStack(spacing: 10) {
                        Spacer()
                            .frame(width: 22)
                        
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Text(file.name)
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .onTapGesture {
                        // Open specific file
                    }
                }
            }
        }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Data Models
struct FavoriteDocument: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let url: URL
    let addedDate: Date
}

struct FolderItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let url: URL
    var fileCount: Int
    var files: [FileItem]
}

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}

struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        SidebarView(selectedItem: .constant(.recentFiles))
            .environmentObject(DocumentManager())
            .frame(width: 250, height: 600)
    }
}
