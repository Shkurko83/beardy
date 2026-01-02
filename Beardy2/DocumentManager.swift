
import SwiftUI
import AppKit
import Combine
internal import UniformTypeIdentifiers

class DocumentManager: ObservableObject {
    // MARK: - Published Properties
    @Published var currentDocument: MarkdownDocument?
    @Published var viewMode: ViewMode = .edit
    @Published var isDarkMode: Bool = true
    @Published var focusMode: Bool = false
    @Published var typewriterMode: Bool = false
    @Published var sidebarToggleSignal: Bool = false
    @Published var sourceMode: Bool = false

    
    // MARK: - Private Properties
    private var recentDocuments: [RecentDocument] = []
    private var favorites: [FavoriteDocument] = []
    private var folders: [FolderItem] = []
    private var cancellables = Set<AnyCancellable>()
    
    // Binding for sidebar
    var showSidebarBinding: Binding<Bool>?
    
    // MARK: - Initialization
    init() {
        loadRecentDocuments()
        loadFavorites()
        loadFolders()
        setupAutoSave()
        
        // Detect system appearance
        if let appearance = NSApp.effectiveAppearance.name.rawValue as? String {
            isDarkMode = appearance.contains("Dark")
        }
    }
    
    // MARK: - Document Operations
    func createNewDocument() {
        let newDoc = MarkdownDocument()
        currentDocument = newDoc
        saveToRecent(newDoc)
    }
    
    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        // Самый надёжный и современный способ
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText
        ]
        
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openDocument(at: url)
        }
    }
    
//    func openDocument() {
//        let panel = NSOpenPanel()
//        panel.allowsMultipleSelection = false
//        panel.canChooseDirectories = false
//        panel.canChooseFiles = true
//        
//        // Define custom content types for markdown
//        if let markdownType = UTType(filenameExtension: "md"),
//           let textType = UTType.plainText {
//            panel.allowedContentTypes = [markdownType, textType]
//        } else {
//            panel.allowedContentTypes = [.plainText]
//        }
//        
//        panel.begin { [weak self] response in
//            if response == .OK, let url = panel.url {
//                self?.openDocument(at: url)
//            }
//        }
//    }
    
    func openDocument(at url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let doc = MarkdownDocument(
                fileName: url.lastPathComponent,
                content: content,
                url: url
            )
            currentDocument = doc
            saveToRecent(doc)
        } catch {
            showError("Failed to open document: \(error.localizedDescription)")
        }
    }
    
    func saveDocument() {
        guard let doc = currentDocument else { return }
        
        if let url = doc.url {
            saveDocument(to: url)
        } else {
            saveDocumentAs()
        }
    }
    
    func saveDocumentAs() {
        guard let doc = currentDocument else { return }
        
        let panel = NSSavePanel()
        
        // Use UTType for markdown
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        } else {
            panel.allowedContentTypes = [.plainText]
        }
        
        panel.nameFieldStringValue = doc.fileName
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.saveDocument(to: url)
            }
        }
    }
    
    private func saveDocument(to url: URL) {
        guard let doc = currentDocument else { return }
        
        do {
            try doc.content.write(to: url, atomically: true, encoding: .utf8)
            currentDocument?.url = url
            currentDocument?.fileName = url.lastPathComponent
            currentDocument?.hasUnsavedChanges = false
            currentDocument?.lastSavedDate = Date()
            
            saveToRecent(doc)
        } catch {
            showError("Failed to save document: \(error.localizedDescription)")
        }
    }
    
    func exportAsPDF() {
        guard let doc = currentDocument else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = doc.fileName.replacingOccurrences(of: ".md", with: ".pdf")
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.exportToPDF(at: url)
            }
        }
    }
    
    private func exportToPDF(at url: URL) {
        // PDF export implementation
        print("Exporting to PDF: \(url)")
        // This would involve rendering the markdown to PDF
    }
    
    func updateContent(_ newContent: String) {
        guard var doc = currentDocument else { return }
        
        if doc.content != newContent {
            doc.content = newContent
            doc.hasUnsavedChanges = true
            doc.lastModifiedDate = Date()
            doc.updateStatistics()
            currentDocument = doc
        }
    }
    
    // MARK: - Recent Documents
    func getRecentDocuments() -> [RecentDocument] {
        return recentDocuments
    }
    
    func openRecentDocument(_ doc: RecentDocument) {
        openDocument(at: doc.url)
    }
    
    func clearRecentDocuments() {
        recentDocuments.removeAll()
        saveRecentDocuments()
    }
    
    private func saveToRecent(_ doc: MarkdownDocument) {
        guard let url = doc.url else { return }
        
        // Remove if already exists
        recentDocuments.removeAll { $0.url == url }
        
        // Add to beginning
        let recent = RecentDocument(
            name: doc.fileName,
            path: url.path,
            url: url,
            modifiedDate: Date()
        )
        recentDocuments.insert(recent, at: 0)
        
        // Keep only last 10
        if recentDocuments.count > 10 {
            recentDocuments = Array(recentDocuments.prefix(10))
        }
        
        saveRecentDocuments()
    }
    
    private func loadRecentDocuments() {
        if let data = UserDefaults.standard.data(forKey: "recentDocuments"),
           let decoded = try? JSONDecoder().decode([RecentDocumentData].self, from: data) {
            recentDocuments = decoded.map { data in
                RecentDocument(
                    name: data.name,
                    path: data.path,
                    url: URL(fileURLWithPath: data.path),
                    modifiedDate: data.modifiedDate
                )
            }
        }
    }
    
    private func saveRecentDocuments() {
        let data = recentDocuments.map { doc in
            RecentDocumentData(
                name: doc.name,
                path: doc.path,
                modifiedDate: doc.modifiedDate
            )
        }
        
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: "recentDocuments")
        }
    }
    
    // MARK: - Favorites
    func getFavorites() -> [FavoriteDocument] {
        return favorites
    }
    
    func toggleFavorite(_ doc: RecentDocument) {
        if let index = favorites.firstIndex(where: { $0.url == doc.url }) {
            favorites.remove(at: index)
        } else {
            let favorite = FavoriteDocument(
                name: doc.name,
                path: doc.path,
                url: doc.url,
                addedDate: Date()
            )
            favorites.append(favorite)
        }
        saveFavorites()
    }
    
    func removeFavorite(_ favorite: FavoriteDocument) {
        favorites.removeAll { $0.id == favorite.id }
        saveFavorites()
    }
    
    func openFavorite(_ favorite: FavoriteDocument) {
        openDocument(at: favorite.url)
    }
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: "favorites"),
           let decoded = try? JSONDecoder().decode([FavoriteDocumentData].self, from: data) {
            favorites = decoded.map { data in
                FavoriteDocument(
                    name: data.name,
                    path: data.path,
                    url: URL(fileURLWithPath: data.path),
                    addedDate: data.addedDate
                )
            }
        }
    }
    
    private func saveFavorites() {
        let data = favorites.map { fav in
            FavoriteDocumentData(
                name: fav.name,
                path: fav.path,
                addedDate: fav.addedDate
            )
        }
        
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: "favorites")
        }
    }
    
    // MARK: - Folders
    func getFolders() -> [FolderItem] {
        return folders
    }
    
    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.addFolder(at: url)
            }
        }
    }
    
    private func addFolder(at url: URL) {
        let folder = FolderItem(
            name: url.lastPathComponent,
            path: url.path,
            url: url,
            fileCount: countMarkdownFiles(in: url),
            files: loadFiles(from: url)
        )
        
        folders.append(folder)
        saveFolders()
    }
    
    func openFolder(_ folder: FolderItem) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }
    
    private func countMarkdownFiles(in url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return 0
        }
        
        var count = 0
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "md" || fileURL.pathExtension == "markdown" {
                count += 1
            }
        }
        return count
    }
    
    private func loadFiles(from url: URL) -> [FileItem] {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return []
        }
        
        var files: [FileItem] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "md" || fileURL.pathExtension == "markdown" {
                files.append(FileItem(name: fileURL.lastPathComponent, url: fileURL))
            }
        }
        return files
    }
    
    private func loadFolders() {
        if let data = UserDefaults.standard.data(forKey: "folders"),
           let decoded = try? JSONDecoder().decode([FolderItemData].self, from: data) {
            folders = decoded.map { data in
                let url = URL(fileURLWithPath: data.path)
                return FolderItem(
                    name: data.name,
                    path: data.path,
                    url: url,
                    fileCount: countMarkdownFiles(in: url),
                    files: loadFiles(from: url)
                )
            }
        }
    }
    
    private func saveFolders() {
        let data = folders.map { folder in
            FolderItemData(name: folder.name, path: folder.path)
        }
        
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: "folders")
        }
    }
    
    // MARK: - Formatting Operations
    func toggleBold() {
        insertFormatting(prefix: "**", suffix: "**")
    }
    
    func toggleItalic() {
        insertFormatting(prefix: "*", suffix: "*")
    }
    
    func toggleStrikethrough() {
        insertFormatting(prefix: "~~", suffix: "~~")
    }
    
    func toggleInlineCode() {
        insertFormatting(prefix: "`", suffix: "`")
    }
    
    func insertHeading(level: Int) {
        let prefix = String(repeating: "#", count: level) + " "
        insertAtCurrentLine(prefix: prefix)
    }
    
    func insertBulletList() {
        insertAtCurrentLine(prefix: "- ")
    }
    
    func insertNumberedList() {
        insertAtCurrentLine(prefix: "1. ")
    }
    
    func insertTaskList() {
        insertAtCurrentLine(prefix: "- [ ] ")
    }
    
    func insertCodeBlock() {
        insertText("\n```\n\n```\n")
    }
    
    func insertBlockquote() {
        insertAtCurrentLine(prefix: "> ")
    }
    
    func insertHorizontalRule() {
        insertText("\n---\n")
    }
    
    func insertLink() {
        insertText("[link text](url)")
    }
    
    func insertImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.insertText("![alt text](\(url.path))")
            }
        }
    }
    
    func insertTable() {
        let tableText = """
        
        | Column 1 | Column 2 | Column 3 |
        |----------|----------|----------|
        | Cell 1   | Cell 2   | Cell 3   |
        | Cell 4   | Cell 5   | Cell 6   |
        
        """
        insertText(tableText)
    }
    
    private func insertFormatting(prefix: String, suffix: String) {
        guard var doc = currentDocument else { return }
        // This is simplified - in real implementation would work with NSTextView selection
        doc.content += prefix + "text" + suffix
        currentDocument = doc
    }
    
    private func insertAtCurrentLine(prefix: String) {
        guard var doc = currentDocument else { return }
        // Simplified implementation
        doc.content += "\n" + prefix
        currentDocument = doc
    }
    
    private func insertText(_ text: String) {
        guard var doc = currentDocument else { return }
        doc.content += text
        currentDocument = doc
    }
    
    // MARK: - View Operations
    func toggleSidebar() {
        sidebarToggleSignal.toggle()
    }
    
    func toggleSourceMode() {
        sourceMode.toggle()
    }
    
    func toggleFocusMode() {
        focusMode.toggle()
    }
    
    func toggleTypewriterMode() {
        typewriterMode.toggle()
    }
    
    func toggleTheme() {
        ThemeService.shared.toggleDarkMode()
    }
    
    func showSettings() {
        if #available(macOS 13, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    
    func showFindPanel() {
        NotificationCenter.default.post(name: .showFindPanel, object: nil)
    }
    
    func showReplacePanel() {
        NotificationCenter.default.post(name: .showReplacePanel, object: nil)
    }
    
    func showImportDialog() {
        // Implementation for import dialog
        print("Show import dialog")
    }
    
    func scrollToHeading(_ heading: HeadingItem) {
        // Implementation to scroll to specific heading
        print("Scroll to heading: \(heading.title)")
    }
    
    // MARK: - Auto-save
    private func setupAutoSave() {
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.autoSave()
            }
            .store(in: &cancellables)
    }
    
    private func autoSave() {
        guard let doc = currentDocument,
              doc.hasUnsavedChanges,
              doc.url != nil else { return }
        
        saveDocument()
    }
    
    // MARK: - Error Handling
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - DocumentManager Singleton Extension
extension DocumentManager {
    private static var _shared: DocumentManager?
    
    static var shared: DocumentManager? {
        get { _shared }
        set { _shared = newValue }
    }
}

// MARK: - Document Model
struct MarkdownDocument {
    var id = UUID()
    var fileName: String
    var content: String
    var url: URL?
    var hasUnsavedChanges: Bool
    var lastModifiedDate: Date
    var lastSavedDate: Date?
    var wordCount: Int
    var characterCount: Int
    var lineCount: Int
    
    init(fileName: String = "Untitled.md", content: String = "", url: URL? = nil) {
        self.fileName = fileName
        self.content = content
        self.url = url
        self.hasUnsavedChanges = false
        self.lastModifiedDate = Date()
        self.wordCount = 0
        self.characterCount = 0
        self.lineCount = 0
        updateStatistics()
    }
    
    mutating func updateStatistics() {
        self.characterCount = content.count
        self.wordCount = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        self.lineCount = content.components(separatedBy: .newlines).count
    }
}

// MARK: - Codable Data Models
struct RecentDocumentData: Codable {
    let name: String
    let path: String
    let modifiedDate: Date
}

struct FavoriteDocumentData: Codable {
    let name: String
    let path: String
    let addedDate: Date
}

struct FolderItemData: Codable {
    let name: String
    let path: String
}

extension Notification.Name {
    static let showFindPanel = Notification.Name("showFindPanel")
    static let showReplacePanel = Notification.Name("showReplacePanel")
}
