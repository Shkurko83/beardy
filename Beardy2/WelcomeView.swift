//
//  WelcomeView.swift
//  Beardy2
//
//  Created by Butt Simpson on 27.12.2025.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct WelcomeView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var themeService: ThemeService
    @State private var recentDocuments: [RecentDocument] = []
    
    var body: some View {
        ZStack {
            // Background
            themeService.currentTheme.colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Logo and Title
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Markdown Editor")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(themeService.currentTheme.colors.text)
                    
                    Text("A minimal markdown editor")
                        .font(.system(size: 16))
                        .foregroundStyle(themeService.currentTheme.colors.text.opacity(0.8))
                }
                .padding(.top, 60)
                
                // Quick Actions
                HStack(spacing: 20) {
                    WelcomeActionButton(
                        icon: "doc.badge.plus",
                        title: "New Document",
                        subtitle: "⌘N",
                        color: .blue
                    ) {
                        documentManager.createNewDocument()
                    }
                    
                    WelcomeActionButton(
                        icon: "folder.badge.plus",
                        title: "Open File",
                        subtitle: "⌘O",
                        color: .green
                    ) {
                        documentManager.openDocument()
                    }
                    
                    WelcomeActionButton(
                        icon: "arrow.down.doc",
                        title: "Import",
                        subtitle: "Drag & Drop",
                        color: .orange
                    ) {
                        documentManager.showImportDialog()
                    }
                }
                .padding(.horizontal, 40)
                
                // Recent Documents
                if !recentDocuments.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Documents")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button("Clear") {
                                clearRecentDocuments()
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 40)
                        
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(recentDocuments.prefix(5)) { doc in
                                    RecentDocumentRow(document: doc) {
                                        documentManager.openRecentDocument(doc)
                                    }
                                }
                            }
                            .padding(.horizontal, 40)
                        }
                        .frame(maxHeight: 200)
                    }
                }
                
                Spacer()
                
                // Footer Tips
                VStack(spacing: 8) {
                    HStack(spacing: 20) {
                        TipItem(icon: "keyboard", text: "⌘K for shortcuts")
                        TipItem(icon: "paintbrush", text: "⌘T for themes")
                        TipItem(icon: "gearshape", text: "⌘, for settings")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            loadRecentDocuments()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private func loadRecentDocuments() {
        // Load from UserDefaults or similar
        recentDocuments = documentManager.getRecentDocuments()
    }
    
    private func clearRecentDocuments() {
        recentDocuments.removeAll()
        documentManager.clearRecentDocuments()
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        documentManager.openDocument(at: url)
                    }
                }
            }
        }
        return true
    }
}

struct WelcomeActionButton: View {
    @EnvironmentObject var themeService: ThemeService
    
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(color)
                    .frame(width: 60, height: 60)
                    .background(color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(themeService.currentTheme.colors.text)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(themeService.currentTheme.colors.text.opacity(0.8))
                }
            }
            .frame(width: 140, height: 140)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeService.currentTheme.colors.text.opacity(0.2))
                    .shadow(
                        color: isHovered ? color.opacity(0.3) : Color.black.opacity(0.1),
                        radius: isHovered ? 12 : 6,
                        x: 0,
                        y: isHovered ? 6 : 3
                    )
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct RecentDocumentRow: View {
    let document: RecentDocument
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    
                    Text(document.path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text(document.modifiedDate, style: .relative)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct TipItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
    }
}

struct RecentDocument: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let url: URL
    let modifiedDate: Date
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
            .environmentObject(DocumentManager())
            .frame(width: 1000, height: 700)
    }
}
