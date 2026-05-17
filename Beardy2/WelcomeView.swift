//
//  WelcomeView.swift
//  Beardy2
//

import SwiftUI
internal import UniformTypeIdentifiers

struct WelcomeView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var themeService: ThemeService
    @State private var recentDocuments: [RecentDocument] = []

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("Markdown Editor")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(themeService.currentTheme.colors.text)

                    Text("A minimal markdown editor")
                        .font(.system(size: 16))
                        .foregroundStyle(themeService.currentTheme.colors.text.opacity(0.8))
                }
                .padding(.top, 48)

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
                .padding(.top, 32)

                if !recentDocuments.isEmpty {
                    recentDocumentsSection
                        .frame(maxHeight: max(160, geometry.size.height - 360))
                        .padding(.top, 24)
                }

                Spacer(minLength: 12)

                VStack(spacing: 8) {
                    HStack(spacing: 20) {
                        TipItem(icon: "keyboard", text: "⌘K for shortcuts")
                        TipItem(icon: "paintbrush", text: "⌘T for themes")
                        TipItem(icon: "gearshape", text: "⌘, for settings")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.bottom, 24)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background(themeService.currentTheme.colors.background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadRecentDocuments() }
        .onChange(of: documentManager.libraryRevision) { _, _ in
            loadRecentDocuments()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    private var recentDocumentsSection: some View {
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
                LazyVStack(spacing: 8) {
                    ForEach(recentDocuments.prefix(20)) { doc in
                        RecentDocumentRow(document: doc) {
                            documentManager.openRecentDocument(doc)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
            }
        }
    }

    private func loadRecentDocuments() {
        recentDocuments = documentManager.getRecentDocuments()
    }

    private func clearRecentDocuments() {
        recentDocuments.removeAll()
        documentManager.clearRecentDocuments()
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        documentManager.openDocument(at: url, inNewTab: true)
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
                    .fill(themeService.currentTheme.colors.text.opacity(0.08))
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
        .onHover { isHovered = $0 }
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
        .onHover { isHovered = $0 }
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
    let bookmark: Data?
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
            .environmentObject(DocumentManager())
            .frame(width: 1000, height: 700)
    }
}
