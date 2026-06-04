
import SwiftUI
import AppKit
import Combine
internal import UniformTypeIdentifiers

class DocumentManager: ObservableObject {
    private var statisticsUpdateWorkItem: DispatchWorkItem?
    private var outlineUpdateWorkItem: DispatchWorkItem?

    // MARK: - Published Properties
    @Published var tabs: [EditorTab] = []
    @Published var selectedTabID: UUID?
    @Published var libraryRevision = 0
    @Published var focusMode: Bool = false
    @Published var typewriterMode: Bool = false
    @Published var sidebarToggleSignal: Bool = false
    @Published var sourceMode: Bool = false
    @Published var showSidebar: Bool = true
    @Published var showOutline: Bool = false
    @Published var outlineHeadings: [HeadingItem] = []
    /// Published so SwiftUI reliably refreshes chrome when Preview / Focus Mode changes.
    @Published private(set) var isReadingChromeActive: Bool = false
    @Published var viewMode: ViewMode = .edit {
        didSet {
            guard oldValue != viewMode else { return }
            if viewMode == .diff, oldValue != .diff {
                prepareDiffMode(enteringFrom: oldValue)
            } else if oldValue == .diff, viewMode != .diff {
                diffCoordinator.isActive = false
            }
            if viewMode != .diff {
                UserDefaults.standard.set(viewMode.rawValue, forKey: Self.viewModeDefaultsKey)
            }
        }
    }

    @Published var diffCoordinator = DiffModeCoordinator()
    /// Bumped when diff HTML changes so SwiftUI reloads the diff web view.
    @Published private(set) var diffRenderRevision: UInt = 0

    /// Comparison source / external file per editor tab.
    private var tabDiffSettingsByTabID: [UUID: TabDiffSettings] = [:]

    private static let viewModeDefaultsKey = "selectedViewMode"

    /// Preview (eye) or Focus Mode (⇧⌘F) — read-only chrome with hidden panels/toolbar.
    var isReadingChromeMode: Bool {
        isReadingChromeActive
    }

    // MARK: - Private Properties
    private var recentDocuments: [RecentDocument] = []
    private var favorites: [FavoriteDocument] = []
    private var folders: [FolderItem] = []
    private var cancellables = Set<AnyCancellable>()
    private var sidebarBeforeReadingChrome: Bool?
    private var outlineBeforeReadingChrome: Bool?
    private var wasReadingChrome = false
    private var undoHistories: [UUID: DocumentUndoHistory] = [:]
    private var isApplyingUndoRedo = false
    private var lastUndoRedoActionTime: Date?

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    var currentDocument: MarkdownDocument? {
        get {
            guard let id = selectedTabID else { return nil }
            return tabs.first(where: { $0.id == id })?.document
        }
        set {
            guard let newValue else {
                if let id = selectedTabID {
                    tabs.removeAll { $0.id == id }
                    selectedTabID = tabs.last?.id
                }
                return
            }
            if let id = selectedTabID, let index = tabs.firstIndex(where: { $0.id == id }) {
                tabs[index].document = newValue
            } else {
                let tab = EditorTab(document: newValue)
                tabs.append(tab)
                selectedTabID = tab.id
            }
        }
    }

    var hasOpenTabs: Bool { !tabs.isEmpty }

    // MARK: - Initialization
    init() {
        loadRecentDocuments()
        loadFavorites()
        loadFolders()
        if let raw = UserDefaults.standard.string(forKey: Self.viewModeDefaultsKey),
           let stored = ViewMode(rawValue: raw),
           stored != .diff {
            viewMode = stored
        }
        focusMode = UserDefaults.standard.bool(forKey: AppConstants.Keys.focusMode)
        syncReadingChromePanels()
        setupAutoSave()
        setupImagePasteObserver()
        setupOutlineHeadingsObserver()
        setupDiffCoordinatorObserver()
    }

    private func setupDiffCoordinatorObserver() {
        diffCoordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func markDiffRenderUpdated() {
        diffRenderRevision &+= 1
        objectWillChange.send()
    }

    private func setupOutlineHeadingsObserver() {
        NotificationCenter.default.publisher(for: .outlineHeadingsDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let items = notification.object as? [HeadingItem] else { return }
                self?.applyOutlineHeadingsFromEditor(items)
            }
            .store(in: &cancellables)
    }

    // MARK: - Reading chrome (Preview / Focus Mode) panel layout

    func syncReadingChromePanels() {
        let active = focusMode || viewMode == .preview || viewMode == .diff

        if active && !wasReadingChrome {
            if sidebarBeforeReadingChrome == nil {
                sidebarBeforeReadingChrome = showSidebar
            }
            if outlineBeforeReadingChrome == nil {
                outlineBeforeReadingChrome = showOutline
            }
            showSidebar = !Self.focusHideSidebarDefault
            showOutline = !Self.focusHideOutlineDefault
        } else if !active && wasReadingChrome {
            if let saved = sidebarBeforeReadingChrome {
                showSidebar = saved
            }
            if let saved = outlineBeforeReadingChrome {
                showOutline = saved
            }
            sidebarBeforeReadingChrome = nil
            outlineBeforeReadingChrome = nil
        }

        wasReadingChrome = active
        isReadingChromeActive = active
    }

    func applyReadingChromePanelDefaultsIfActive() {
        guard isReadingChromeActive else { return }
        showSidebar = !Self.focusHideSidebarDefault
        showOutline = !Self.focusHideOutlineDefault
    }

    private static var focusHideSidebarDefault: Bool {
        UserDefaults.standard.object(forKey: AppConstants.Keys.focusHideSidebar) as? Bool ?? true
    }

    private static var focusHideOutlineDefault: Bool {
        UserDefaults.standard.object(forKey: AppConstants.Keys.focusHideOutline) as? Bool ?? true
    }

    private func setupImagePasteObserver() {
        NotificationCenter.default.addObserver(
            forName: .processImageFile,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let data = notification.userInfo?["data"] as? Data,
                  let filename = notification.userInfo?["filename"] as? String else { return }
            self.insertImageFromData(data, suggestedFilename: filename)
        }
    }
    
    // MARK: - Tabs
    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        if let previous = selectedTabID, previous != id {
            captureDiffSettings(forTabID: previous)
        }
        DocumentSecurityAccess.deactivate()
        selectedTabID = id
        applyDiffSettings(forTabID: id)
        if let tab = tabs.first(where: { $0.id == id }) {
            ensureUndoHistory(for: id, content: tab.document.content)
        }
        refreshUndoAvailability()
        if let url = currentDocument?.url {
            DocumentSecurityAccess.activate(document: url)
        }
        if viewMode == .diff {
            reloadDiffModeForCurrentTab(resetSnapshotSelection: false)
        }
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]

        if tab.document.hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = "Save \"\(tab.document.fileName)\"?"
            alert.informativeText = "Your changes will be lost if you don't save."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let previous = selectedTabID
                selectedTabID = id
                saveDocument()
                selectedTabID = previous
            } else if response == .alertThirdButtonReturn {
                return
            }
        }

        undoHistories.removeValue(forKey: id)
        tabDiffSettingsByTabID.removeValue(forKey: id)
        tabs.remove(at: index)
        if selectedTabID == id {
            if tabs.isEmpty {
                selectedTabID = nil
            } else {
                let nextIndex = min(index, tabs.count - 1)
                selectedTabID = tabs[nextIndex].id
            }
        }
        if let url = currentDocument?.url {
            DocumentSecurityAccess.activate(document: url)
        } else {
            DocumentSecurityAccess.deactivate()
        }
    }

    /// Moves a tab so it sits at `destinationIndex` (0 = before first tab, `tabs.count` = after last).
    func moveTab(from sourceID: UUID, toIndex destinationIndex: Int) {
        guard let fromIndex = tabs.firstIndex(where: { $0.id == sourceID }) else { return }
        var dest = min(max(0, destinationIndex), tabs.count)
        if fromIndex < dest { dest -= 1 }
        guard fromIndex != dest else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            let tab = tabs.remove(at: fromIndex)
            tabs.insert(tab, at: dest)
        }
    }

    private func openInNewTab(_ doc: MarkdownDocument) {
        if let url = doc.url,
           let existing = tabs.first(where: { $0.document.url?.standardizedFileURL == url.standardizedFileURL }) {
            selectTab(existing.id)
            return
        }
        let tab = EditorTab(document: doc)
        tabs.append(tab)
        if let previous = selectedTabID {
            captureDiffSettings(forTabID: previous)
        }
        selectedTabID = tab.id
        applyDiffSettings(forTabID: tab.id)
        resetUndoHistory(for: tab.id, content: doc.content)
        if viewMode == .diff {
            reloadDiffModeForCurrentTab(resetSnapshotSelection: false)
        }
    }

    private func nextUntitledFileName() -> String {
        var usedNumbers = Set<Int>()
        for tab in tabs {
            let name = tab.document.fileName
            if name == "Untitled.md" {
                usedNumbers.insert(1)
                continue
            }
            guard name.hasPrefix("Untitled"), name.hasSuffix(".md") else { continue }
            let middle = String(name.dropFirst("Untitled".count).dropLast(3))
            if middle.isEmpty {
                usedNumbers.insert(1)
            } else if let number = Int(middle) {
                usedNumbers.insert(number)
            }
        }
        var candidate = 1
        while usedNumbers.contains(candidate) { candidate += 1 }
        return candidate == 1 ? "Untitled.md" : "Untitled\(candidate).md"
    }

    // MARK: - Document Operations
    func createNewDocument() {
        let newDoc = MarkdownDocument(fileName: nextUntitledFileName())
        openInNewTab(newDoc)
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText
        ]

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Self.grantAccessAndSaveBookmarks(for: url)
            self?.openDocument(at: url, inNewTab: true)
        }
    }

    func openDocument(at url: URL, inNewTab: Bool = true) {
        let resolved = SecurityBookmarkStore.resolveURL(path: url.path) ?? url
        Self.grantAccessAndSaveBookmarks(for: resolved)
        DocumentSecurityAccess.activate(document: resolved)

        do {
            let content = try String(contentsOf: resolved, encoding: .utf8)
            let doc = MarkdownDocument(
                fileName: resolved.lastPathComponent,
                content: content,
                url: resolved
            )
            _ = SnapshotStore.append(content: content, label: SnapshotStore.onOpenLabel, to: doc)
            if inNewTab {
                openInNewTab(doc)
            } else {
                currentDocument = doc
            }
            saveToRecent(doc)
        } catch {
            DocumentSecurityAccess.deactivate()
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
            guard response == .OK, let url = panel.url else { return }
            Self.grantAccessAndSaveBookmarks(for: url)
            self?.saveDocument(to: url)
        }
    }
    
    private func saveDocument(to url: URL) {
        guard let id = selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        var doc = tabs[index].document

        do {
            try doc.content.write(to: url, atomically: true, encoding: .utf8)
            doc.url = url
            doc.fileName = url.lastPathComponent
            doc.hasUnsavedChanges = false
            doc.lastSavedDate = Date()
            tabs[index].document = doc
            diffCoordinator.snapshots = SnapshotStore.append(
                content: doc.content,
                label: SnapshotStore.saveLabel,
                to: doc
            )

            Self.grantAccessAndSaveBookmarks(for: url)
            DocumentSecurityAccess.activate(document: url)
            saveToRecent(doc)

            if viewMode == .diff {
                reloadDiffModeForCurrentTab(resetSnapshotSelection: false)
            }
        } catch {
            showError("Failed to save document: \(error.localizedDescription)")
        }
    }

    // MARK: - Diff Mode

    func toggleDiffMode() {
        if viewMode == .diff {
            exitDiffMode()
        } else {
            diffCoordinator.previousMode = viewMode
            viewMode = .diff
        }
    }

    func exitDiffMode() {
        let restore = diffCoordinator.previousMode
        diffCoordinator.isActive = false
        if viewMode == .diff {
            viewMode = restore == .diff ? .preview : restore
        }
    }

    func prepareDiffMode(enteringFrom mode: ViewMode) {
        diffCoordinator.previousMode = mode
        diffCoordinator.isActive = true
        if let tabID = selectedTabID {
            applyDiffSettings(forTabID: tabID)
        }
        reloadDiffModeForCurrentTab(resetSnapshotSelection: false)
    }

    private func captureDiffSettings(forTabID tabID: UUID) {
        tabDiffSettingsByTabID[tabID] = TabDiffSettings(
            comparisonSource: diffCoordinator.comparisonSource,
            selectedSnapshotID: diffCoordinator.selectedSnapshotID,
            externalBaseline: diffCoordinator.externalBaseline
        )
    }

    private func applyDiffSettings(forTabID tabID: UUID) {
        let settings = tabDiffSettingsByTabID[tabID] ?? TabDiffSettings()
        diffCoordinator.comparisonSource = settings.comparisonSource
        diffCoordinator.selectedSnapshotID = settings.selectedSnapshotID
        diffCoordinator.externalBaseline = settings.externalBaseline
    }

    private func persistDiffSettingsForCurrentTab() {
        guard let tabID = selectedTabID else { return }
        captureDiffSettings(forTabID: tabID)
    }

    func reloadDiffModeForCurrentTab(resetSnapshotSelection: Bool = false) {
        guard viewMode == .diff else { return }
        if resetSnapshotSelection {
            diffCoordinator.selectedSnapshotID = nil
            diffCoordinator.comparisonSource = .previousVersion
        }
        guard let doc = currentDocument else {
            diffCoordinator.snapshots = []
            diffCoordinator.diffResult = nil
            diffCoordinator.placeholderMessage = nil
            diffCoordinator.resetNavigation(changeCount: 0)
            return
        }

        var snapshots = SnapshotStore.load(for: doc)
        if snapshots.isEmpty {
            snapshots = SnapshotStore.append(
                content: doc.content,
                label: SnapshotStore.onOpenLabel,
                to: doc
            )
        }
        if doc.hasUnsavedChanges {
            let needsUnsavedSnapshot = snapshots.first?.label != "Unsaved"
                || snapshots.first?.content != doc.content
            if needsUnsavedSnapshot {
                snapshots = SnapshotStore.append(
                    content: doc.content,
                    label: "Unsaved",
                    to: doc,
                    skipIfSameAsLatest: true
                )
            }
        }
        diffCoordinator.snapshots = snapshots
        refreshDiffRender()
    }

    func selectDiffSnapshot(id: UUID?) {
        if let id {
            diffCoordinator.comparisonSource = .snapshot(id)
            diffCoordinator.selectedSnapshotID = id
        } else {
            diffCoordinator.comparisonSource = .previousVersion
            diffCoordinator.selectedSnapshotID = nil
        }
        persistDiffSettingsForCurrentTab()
        refreshDiffRender()
    }

    func pickExternalComparisonFile() {
        guard currentDocument != nil else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let md = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [md, .plainText]
        } else {
            panel.allowedContentTypes = [.plainText]
        }
        panel.title = "Compare With File"
        panel.prompt = "Compare"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Self.grantAccessAndSaveBookmarks(for: url)
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                DispatchQueue.main.async {
                    self?.diffCoordinator.externalBaseline = ExternalDiffBaseline(
                        url: url,
                        fileName: url.lastPathComponent,
                        content: content
                    )
                    self?.diffCoordinator.comparisonSource = .externalFile
                    self?.persistDiffSettingsForCurrentTab()
                    self?.refreshDiffRender()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showError("Could not read file: \(error.localizedDescription)")
                }
            }
        }
    }

    func clearExternalComparison() {
        diffCoordinator.clearExternalBaseline()
        persistDiffSettingsForCurrentTab()
        refreshDiffRender()
    }

    func setDiffGranularity(_ granularity: DiffGranularity) {
        diffCoordinator.granularity = granularity
        refreshDiffRender(bumpViewIdentity: false)
    }

    func refreshDiffRender(bumpViewIdentity: Bool = true) {
        if let doc = currentDocument {
            diffCoordinator.snapshots = SnapshotStore.load(for: doc)
        }

        guard let doc = currentDocument else {
            diffCoordinator.diffResult = nil
            diffCoordinator.resetNavigation(changeCount: 0)
            markDiffRenderUpdated()
            return
        }

        guard let baseline = diffBaselineContent(for: doc) else {
            diffCoordinator.diffResult = nil
            switch diffCoordinator.comparisonSource {
            case .externalFile:
                diffCoordinator.placeholderMessage = "Choose a file to compare using “Compare with file…” in the toolbar."
            default:
                if diffCoordinator.snapshots.isEmpty {
                    diffCoordinator.placeholderMessage =
                        "No version history yet. Save once (⌘S), edit, save again, then open Diff — or use Compare with file…"
                } else {
                    diffCoordinator.placeholderMessage =
                        "No older version to compare. Save after editing, or pick a snapshot / external file from the Comparing menu."
                }
            }
            diffCoordinator.resetNavigation(changeCount: 0)
            if bumpViewIdentity { markDiffRenderUpdated() }
            return
        }

        if baseline == doc.content {
            diffCoordinator.diffResult = nil
            diffCoordinator.placeholderMessage =
                "The comparison version is identical to the current document. Pick an older snapshot or another file."
            diffCoordinator.resetNavigation(changeCount: 0)
            if bumpViewIdentity { markDiffRenderUpdated() }
            return
        }

        diffCoordinator.placeholderMessage = nil
        let chunks = DiffEngine.compute(
            current: doc.content,
            comparison: baseline,
            granularity: diffCoordinator.granularity,
            documentURL: doc.url
        )
        let theme = ThemeService.shared
        let css = theme.generateCSS(colors: theme.colors)
        let result = DiffHTMLBuilder.build(
            chunks: chunks,
            documentURL: doc.url,
            isDark: theme.isDarkMode,
            themeCSS: css,
            codeTheme: theme.currentCodeTheme.rawValue
        )
        diffCoordinator.diffResult = result
        diffCoordinator.resetNavigation(changeCount: result.changeCount)
        if bumpViewIdentity { markDiffRenderUpdated() }
        else { objectWillChange.send() }
    }

    /// Baseline text for comparison; `nil` when nothing suitable exists.
    func diffBaselineContent(for doc: MarkdownDocument) -> String? {
        switch diffCoordinator.comparisonSource {
        case .externalFile:
            return diffCoordinator.externalBaseline?.content

        case .snapshot(let id):
            return diffCoordinator.snapshots.first(where: { $0.id == id })?.content

        case .previousVersion:
            return SnapshotStore.previousDifferentSnapshot(
                in: diffCoordinator.snapshots,
                current: doc.content
            )?.content
        }
    }

    func diffNextChange() {
        guard diffCoordinator.totalChanges > 0 else { return }
        var next = diffCoordinator.currentChangeIndex + 1
        if next > diffCoordinator.totalChanges { next = 1 }
        diffCoordinator.currentChangeIndex = next
    }

    func diffPreviousChange() {
        guard diffCoordinator.totalChanges > 0 else { return }
        var prev = diffCoordinator.currentChangeIndex - 1
        if prev < 1 { prev = diffCoordinator.totalChanges }
        diffCoordinator.currentChangeIndex = prev
    }

    func focusDiffChange(_ index: Int) {
        guard index >= 1, index <= diffCoordinator.totalChanges else { return }
        diffCoordinator.currentChangeIndex = index
    }

    /// Starts security-scoped access and stores bookmarks for the file and its parent folder (required for image copy).
    private static func grantAccessAndSaveBookmarks(for fileURL: URL) {
        _ = fileURL.startAccessingSecurityScopedResource()
        let directoryURL = fileURL.deletingLastPathComponent()
        _ = directoryURL.startAccessingSecurityScopedResource()
        SecurityBookmarkStore.saveBookmark(for: fileURL)
        SecurityBookmarkStore.saveBookmark(for: directoryURL)
    }
    
    func exportAsPDF() {
        exportDocument(as: .pdf)
    }
    
    func exportDocument(as format: ExportService.ExportFormat) {
        guard let doc = currentDocument else { return }
        
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedExportFileName(for: doc, format: format)
        
        switch format {
        case .pdf:
            panel.allowedContentTypes = [.pdf]
        case .html, .htmlPlain:
            panel.allowedContentTypes = [.html]
        case .docx:
            if let type = UTType(filenameExtension: "docx") {
                panel.allowedContentTypes = [type]
            }
        case .odt:
            if let type = UTType(filenameExtension: "odt") {
                panel.allowedContentTypes = [type]
            }
        case .rtf:
            panel.allowedContentTypes = [.rtf]
        case .epub:
            if let type = UTType(filenameExtension: "epub") {
                panel.allowedContentTypes = [type]
            }
        case .latex:
            if let type = UTType(filenameExtension: "tex") {
                panel.allowedContentTypes = [type]
            }
        case .plainText:
            panel.allowedContentTypes = [.plainText]
        case .markdown:
            if let md = UTType(filenameExtension: "md") {
                panel.allowedContentTypes = [md]
            }
        }
        
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.performExport(format: format, to: url, document: doc)
        }
    }
    
    private func suggestedExportFileName(
        for doc: MarkdownDocument,
        format: ExportService.ExportFormat
    ) -> String {
        let base = doc.url?.deletingPathExtension().lastPathComponent
            ?? doc.fileName.replacingOccurrences(of: ".md", with: "")
        return "\(base).\(format.fileExtension)"
    }
    
    private func makeExportOptions(for format: ExportService.ExportFormat) -> ExportService.ExportOptions {
        var options = ExportService.ExportOptions()
        let margins = UserDefaults.standard.double(forKey: AppConstants.Keys.exportPDFMargins)
        options.margins = margins >= 36 ? CGFloat(margins) : AppConstants.Export.defaultPDFMargins
        options.includeCSS = format.includesStyles
        options.includePageNumbers = false
        options.paperSize = .a4
        return options
    }
    
    private func performExport(
        format: ExportService.ExportFormat,
        to url: URL,
        document doc: MarkdownDocument
    ) {
        let options = makeExportOptions(for: format)
        ExportService.shared.export(
            markdown: doc.content,
            to: url,
            documentURL: doc.url,
            format: format,
            options: options
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let savedURL):
                    self?.showExportSuccess(savedURL, format: format)
                case .failure(let error):
                    self?.showError("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showExportSuccess(_ url: URL, format: ExportService.ExportFormat) {
        let alert = NSAlert()
        alert.messageText = "Export Complete"
        alert.informativeText = "Saved as \(format.displayName) to:\n\(url.path)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Reveal in Finder")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    func updateContent(_ newContent: String, recordUndo: Bool = true) {
        guard let id = selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        var doc = tabs[index].document
        guard doc.content != newContent else { return }

        if recordUndo && !isApplyingUndoRedo {
            ensureUndoHistory(for: id, content: doc.content)
            if var history = undoHistories[id] {
                history.record(content: newContent)
                undoHistories[id] = history
            }
            refreshUndoAvailability()
        }

        doc.content = newContent
        doc.hasUnsavedChanges = true
        doc.lastModifiedDate = Date()
        tabs[index].document = doc
        scheduleStatisticsUpdate(tabIndex: index)
        scheduleOutlineUpdate()
    }

    func resetUndoHistory(for tabID: UUID, content: String) {
        var history = DocumentUndoHistory()
        history.reset(with: content)
        undoHistories[tabID] = history
        refreshUndoAvailability()
    }

    func ensureUndoHistory(for tabID: UUID, content: String) {
        if undoHistories[tabID] == nil {
            resetUndoHistory(for: tabID, content: content)
        }
    }

    func requestUndo() {
        execEditorJS("window.cmEditor?.performUndo?.();")
    }

    func requestRedo() {
        execEditorJS("window.cmEditor?.performRedo?.();")
    }

    func undo(editorSnapshot: String? = nil) {
        guard shouldProcessUndoRedo() else { return }
        commitEditorSnapshot(editorSnapshot)
        guard let id = selectedTabID,
              var history = undoHistories[id],
              let content = history.undo() else { return }
        undoHistories[id] = history
        applyHistoryContent(content)
    }

    func redo(editorSnapshot: String? = nil) {
        guard shouldProcessUndoRedo() else { return }
        commitEditorSnapshot(editorSnapshot)
        guard let id = selectedTabID,
              var history = undoHistories[id],
              let content = history.redo() else { return }
        undoHistories[id] = history
        applyHistoryContent(content)
    }

    private func commitEditorSnapshot(_ snapshot: String?) {
        guard let snap = snapshot,
              let id = selectedTabID,
              var history = undoHistories[id] else { return }
        if history.states.indices.contains(history.index), history.states[history.index] != snap {
            history.replaceCurrent(with: snap)
            undoHistories[id] = history
        }
    }

    private func applyHistoryContent(_ content: String) {
        guard let id = selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        isApplyingUndoRedo = true
        defer {
            isApplyingUndoRedo = false
            refreshUndoAvailability()
        }

        var doc = tabs[index].document
        doc.content = content
        doc.hasUnsavedChanges = true
        doc.lastModifiedDate = Date()
        tabs[index].document = doc
        scheduleStatisticsUpdate(tabIndex: index)
        scheduleOutlineUpdate()

        NotificationCenter.default.post(name: .editorHistoryContentApplied, object: content)
        execEditorJS("window.cmEditor?.applyHistoryContent(`\(escapeForJS(content))`);")
    }

    private func shouldProcessUndoRedo() -> Bool {
        let now = Date()
        if let last = lastUndoRedoActionTime, now.timeIntervalSince(last) < 0.12 {
            return false
        }
        lastUndoRedoActionTime = now
        return true
    }

    private func refreshUndoAvailability() {
        guard let id = selectedTabID, let history = undoHistories[id] else {
            canUndo = false
            canRedo = false
            return
        }
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    func requestOutlineHeadings(immediately: Bool = false) {
        if let content = currentDocument?.content {
            outlineHeadings = Self.parseHeadings(from: content)
        } else {
            outlineHeadings = []
        }

        outlineUpdateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.execEditorJS("window.cmEditor?.publishOutlineHeadings?.();")
        }
        outlineUpdateWorkItem = work
        if immediately {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }

    func applyOutlineHeadingsFromEditor(_ items: [HeadingItem]) {
        outlineHeadings = items
    }

    private func scheduleOutlineUpdate() {
        requestOutlineHeadings(immediately: false)
    }

    private func scheduleStatisticsUpdate(tabIndex: Int) {
        statisticsUpdateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  tabIndex < self.tabs.count else { return }
            var doc = self.tabs[tabIndex].document
            doc.updateStatistics()
            self.tabs[tabIndex].document = doc
        }
        statisticsUpdateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    
    // MARK: - Recent Documents
    func getRecentDocuments() -> [RecentDocument] {
        return recentDocuments
    }
    
    func openRecentDocument(_ doc: RecentDocument) {
        guard let url = SecurityBookmarkStore.resolveURL(path: doc.path, bookmark: doc.bookmark) else {
            promptReopenMissingFile(storedPath: doc.path, title: doc.name)
            return
        }
        openDocument(at: url, inNewTab: true)
    }

    private func promptReopenMissingFile(storedPath: String, title: String) {
        let alert = NSAlert()
        alert.messageText = "Cannot access file"
        alert.informativeText = "\"\(title)\" is not available. Please select the file again."
        alert.addButton(withTitle: "Choose File…")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            .plainText
        ]
        panel.directoryURL = URL(fileURLWithPath: (storedPath as NSString).deletingLastPathComponent)
        panel.nameFieldStringValue = (storedPath as NSString).lastPathComponent
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Self.grantAccessAndSaveBookmarks(for: url)
            self?.openDocument(at: url, inNewTab: true)
        }
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
            modifiedDate: Date(),
            bookmark: SecurityBookmarkStore.bookmarkData(for: url.path)
        )
        recentDocuments.insert(recent, at: 0)
        
        if recentDocuments.count > 20 {
            recentDocuments = Array(recentDocuments.prefix(20))
        }
        
        saveRecentDocuments()
        bumpLibraryRevision()
    }

    private func bumpLibraryRevision() {
        libraryRevision += 1
    }
    
    private func loadRecentDocuments() {
        if let data = UserDefaults.standard.data(forKey: "recentDocuments"),
           let decoded = try? JSONDecoder().decode([RecentDocumentData].self, from: data) {
            recentDocuments = decoded.map { data in
                let url = SecurityBookmarkStore.resolveURL(path: data.path, bookmark: data.bookmark)
                    ?? URL(fileURLWithPath: data.path)
                return RecentDocument(
                    name: data.name,
                    path: data.path,
                    url: url,
                    modifiedDate: data.modifiedDate,
                    bookmark: data.bookmark
                )
            }
        }
    }
    
    private func saveRecentDocuments() {
        let data = recentDocuments.map { doc in
            RecentDocumentData(
                name: doc.name,
                path: doc.path,
                modifiedDate: doc.modifiedDate,
                bookmark: SecurityBookmarkStore.bookmarkData(for: doc.path) ?? doc.bookmark
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
    
    func isFavorite(path: String) -> Bool {
        favorites.contains { $0.path == path }
    }

    func toggleFavoriteForActiveDocument() {
        guard let doc = currentDocument, let url = doc.url else { return }
        let recent = RecentDocument(
            name: doc.fileName,
            path: url.path,
            url: url,
            modifiedDate: Date(),
            bookmark: SecurityBookmarkStore.bookmarkData(for: url.path)
        )
        toggleFavorite(recent)
    }

    func toggleFavorite(_ doc: RecentDocument) {
        if let index = favorites.firstIndex(where: { $0.path == doc.path }) {
            favorites.remove(at: index)
        } else {
            let favorite = FavoriteDocument(
                name: doc.name,
                path: doc.path,
                url: doc.url,
                addedDate: Date(),
                bookmark: SecurityBookmarkStore.bookmarkData(for: doc.path) ?? doc.bookmark
            )
            favorites.append(favorite)
        }
        saveFavorites()
        bumpLibraryRevision()
    }
    
    func removeFavorite(_ favorite: FavoriteDocument) {
        favorites.removeAll { $0.id == favorite.id }
        saveFavorites()
        bumpLibraryRevision()
    }
    
    func openFavorite(_ favorite: FavoriteDocument) {
        guard let url = SecurityBookmarkStore.resolveURL(path: favorite.path, bookmark: favorite.bookmark) else {
            promptReopenMissingFile(storedPath: favorite.path, title: favorite.name)
            return
        }
        openDocument(at: url, inNewTab: true)
    }
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: "favorites"),
           let decoded = try? JSONDecoder().decode([FavoriteDocumentData].self, from: data) {
            favorites = decoded.map { data in
                let url = SecurityBookmarkStore.resolveURL(path: data.path, bookmark: data.bookmark)
                    ?? URL(fileURLWithPath: data.path)
                return FavoriteDocument(
                    name: data.name,
                    path: data.path,
                    url: url,
                    addedDate: data.addedDate,
                    bookmark: data.bookmark
                )
            }
        }
    }
    
    private func saveFavorites() {
        let data = favorites.map { fav in
            FavoriteDocumentData(
                name: fav.name,
                path: fav.path,
                addedDate: fav.addedDate,
                bookmark: SecurityBookmarkStore.bookmarkData(for: fav.path) ?? fav.bookmark
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
                _ = url.startAccessingSecurityScopedResource()
                SecurityBookmarkStore.saveBookmark(for: url)
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
            files: loadFiles(from: url),
            bookmark: SecurityBookmarkStore.bookmarkData(for: url.path)
        )
        
        folders.append(folder)
        saveFolders()
        bumpLibraryRevision()
    }
    
    func openFolder(_ folder: FolderItem) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }
    
    private func countMarkdownFiles(in url: URL) -> Int {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
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
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return []
        }
        
        var files: [FileItem] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "md" || fileURL.pathExtension == "markdown" {
                SecurityBookmarkStore.saveBookmark(for: fileURL)
                files.append(FileItem(name: fileURL.lastPathComponent, url: fileURL))
            }
        }
        return files
    }
    
    private func loadFolders() {
        if let data = UserDefaults.standard.data(forKey: "folders"),
           let decoded = try? JSONDecoder().decode([FolderItemData].self, from: data) {
            folders = decoded.map { data in
                let url = SecurityBookmarkStore.resolveURL(path: data.path, bookmark: data.bookmark)
                    ?? URL(fileURLWithPath: data.path)
                return FolderItem(
                    name: data.name,
                    path: data.path,
                    url: url,
                    fileCount: countMarkdownFiles(in: url),
                    files: loadFiles(from: url),
                    bookmark: data.bookmark
                )
            }
        }
    }
    
    private func saveFolders() {
        let data = folders.map { folder in
            FolderItemData(
                name: folder.name,
                path: folder.path,
                bookmark: SecurityBookmarkStore.bookmarkData(for: folder.path) ?? folder.bookmark
            )
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
        execEditorJS("window.cmEditor?.toggleList('bullet');")
    }
    
    func insertNumberedList() {
        execEditorJS("window.cmEditor?.toggleList('ordered');")
    }
    
    func insertTaskList() {
        execEditorJS("window.cmEditor?.toggleList('task');")
    }
    
    func insertCodeBlock() {
        execEditorJS("window.cmEditor?.insertCodeBlock();")
    }
    
    func insertBlockquote() {
        insertAtCurrentLine(prefix: "> ")
    }
    
    func insertHorizontalRule() {
        insertText("\n---\n")
    }
    
    func insertLink() {
        // Проверяем клипборд на наличие URL
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        let isURL = clipboard.hasPrefix("http://") ||
        clipboard.hasPrefix("https://") ||
        clipboard.hasPrefix("ftp://")
        
        let urlArg = isURL ? clipboard
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "'", with: "\\'") : ""
        
        execEditorJS("window.cmEditor?.insertLink(`\(urlArg)`);")
    }
    
    func insertImage() {
        if !hasOpenTabs { createNewDocument() }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.title = "Choose Image"
        panel.prompt = "Insert"
        
        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            let sourceAccess = url.startAccessingSecurityScopedResource()
            DispatchQueue.main.async {
                defer {
                    if sourceAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                self.showImageInsertDialog(url: url)
            }
        }
    }

    func showImageInsertDialog(url: URL) {
        let alert = NSAlert()
        alert.messageText = "Insert Image"
        alert.informativeText = "Choose how to reference this image in the document"
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")

        let hasSavedDocument = currentDocument?.url != nil
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))

        let altLabel = NSTextField(labelWithString: "Alt text:")
        altLabel.frame = NSRect(x: 0, y: 168, width: 80, height: 20)
        let altField = NSTextField(frame: NSRect(x: 90, y: 166, width: 280, height: 24))
        altField.placeholderString = "Image description"
        altField.stringValue = url.deletingPathExtension().lastPathComponent

        let titleLabel = NSTextField(labelWithString: "Title:")
        titleLabel.frame = NSRect(x: 0, y: 136, width: 80, height: 20)
        let titleField = NSTextField(frame: NSRect(x: 90, y: 134, width: 280, height: 24))
        titleField.placeholderString = "Tooltip on hover (optional)"

        let widthLabel = NSTextField(labelWithString: "Width:")
        widthLabel.frame = NSRect(x: 0, y: 104, width: 80, height: 20)
        let widthField = NSTextField(frame: NSRect(x: 90, y: 102, width: 80, height: 24))
        widthField.placeholderString = "100"
        widthField.stringValue = "100"
        let widthUnitLabel = NSTextField(labelWithString: "%")
        widthUnitLabel.frame = NSRect(x: 178, y: 104, width: 20, height: 20)

        let alignLabel = NSTextField(labelWithString: "Alignment:")
        alignLabel.frame = NSRect(x: 0, y: 72, width: 100, height: 20)
        let alignPopup = NSPopUpButton(frame: NSRect(x: 110, y: 70, width: 180, height: 24))
        alignPopup.addItems(withTitles: ["None", "Left", "Center", "Right"])

        let copyCheckbox = NSButton(checkboxWithTitle: "Copy image to folder containing document", target: nil, action: nil)
        copyCheckbox.frame = NSRect(x: 0, y: 18, width: 360, height: 20)
        copyCheckbox.state = (hasSavedDocument && ImageInsertionHelper.copyImagesToDocumentFolder) ? .on : .off
        copyCheckbox.isEnabled = hasSavedDocument

        let copyHint = NSTextField(labelWithString: hasSavedDocument
            ? "Recommended: keep the .md file portable with its images"
            : "Save the document first to copy images beside it")
        copyHint.frame = NSRect(x: 22, y: 2, width: 350, height: 14)
        copyHint.font = .systemFont(ofSize: 10)
        copyHint.textColor = .secondaryLabelColor

        let pathLabel = NSTextField(labelWithString: url.lastPathComponent)
        pathLabel.frame = NSRect(x: 0, y: 50, width: 360, height: 16)
        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle

        container.addSubview(altLabel); container.addSubview(altField)
        container.addSubview(titleLabel); container.addSubview(titleField)
        container.addSubview(widthLabel); container.addSubview(widthField)
        container.addSubview(widthUnitLabel); container.addSubview(alignLabel)
        container.addSubview(alignPopup)
        container.addSubview(pathLabel)
        container.addSubview(copyCheckbox)
        container.addSubview(copyHint)
        alert.accessoryView = container

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let alt = altField.stringValue.isEmpty ? "image" : altField.stringValue
        let title = titleField.stringValue
        let widthValue = Int(widthField.stringValue) ?? 100
        let alignIndex = alignPopup.indexOfSelectedItem
        let alignment = ImageAlignmentOption(rawValue: alignIndex) ?? .none
        let shouldCopy = copyCheckbox.state == .on
        ImageInsertionHelper.copyImagesToDocumentFolder = shouldCopy

        let strategy: ImagePathStrategy = shouldCopy ? .copyBesideDocument : .useOriginalPath

        do {
            let imageSource = try ImageInsertionHelper.imagePath(
                from: url,
                documentURL: currentDocument?.url,
                strategy: strategy
            )

            let markdown = ImageInsertionHelper.buildMarkdown(
                imagePath: imageSource,
                alt: alt,
                title: title,
                widthPercent: widthValue,
                alignment: alignment
            )

            insertMarkdownSnippet(markdown)
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Вставка из буфера / drag-and-drop — тот же диалог, что и для файла.
    func insertImageFromData(_ data: Data, suggestedFilename: String) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(suggestedFilename)
        do {
            try data.write(to: tempURL, options: .atomic)
            showImageInsertDialog(url: tempURL)
        } catch {
            showError("Could not process image from clipboard")
        }
    }

    /// Вставляет Markdown в позицию курсора в WebView-редакторе.
    func insertMarkdownSnippet(_ markdown: String) {
        guard selectedTabID != nil else { return }

        if let docURL = currentDocument?.url {
            let folderPath = docURL.deletingLastPathComponent().path
            execEditorJS("window.cmEditor?.setDocumentPath(`\(escapeForJS(folderPath))`);")
        }

        insertText(markdown)
    }

    private func execEditorJS(_ js: String) {
        NotificationCenter.default.post(name: .editorExecJS, object: js)
    }

    
    func insertTable() {
        let alert = NSAlert()
        alert.messageText = "Insert Table"
        alert.informativeText = "Choose the number of rows and columns."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 72))

        let rowsLabel = NSTextField(labelWithString: "Rows:")
        rowsLabel.frame = NSRect(x: 16, y: 44, width: 72, height: 20)
        rowsLabel.alignment = .right

        let rowsField = NSTextField(frame: NSRect(x: 100, y: 40, width: 64, height: 24))
        rowsField.stringValue = "3"
        rowsField.alignment = .right

        let colsLabel = NSTextField(labelWithString: "Columns:")
        colsLabel.frame = NSRect(x: 16, y: 12, width: 72, height: 20)
        colsLabel.alignment = .right

        let colsField = NSTextField(frame: NSRect(x: 100, y: 8, width: 64, height: 24))
        colsField.stringValue = "3"
        colsField.alignment = .right

        accessory.addSubview(rowsLabel)
        accessory.addSubview(rowsField)
        accessory.addSubview(colsLabel)
        accessory.addSubview(colsField)
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let rows = max(2, Int(rowsField.stringValue) ?? 3)
        let cols = max(1, Int(colsField.stringValue) ?? 3)
        insertText(buildGFMTable(rows: rows, columns: cols))
    }

    private func buildGFMTable(rows: Int, columns: Int) -> String {
        let header = (1...columns).map { "Column \($0)" }
        var lines: [String] = []
        lines.append("| " + header.joined(separator: " | ") + " |")
        lines.append("| " + header.map { _ in "---" }.joined(separator: " | ") + " |")
        for _ in 1..<rows {
            let cells = (1...columns).map { _ in " " }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return "\n" + lines.joined(separator: "\n") + "\n"
    }
    
    private func insertFormatting(prefix: String, suffix: String) {
        let escapedPrefix = escapeForJS(prefix)
        let escapedSuffix = escapeForJS(suffix)
        execEditorJS("window.cmEditor?.insertFormatting(`\(escapedPrefix)`, `\(escapedSuffix)`);")
    }

    private func insertAtCurrentLine(prefix: String) {
        execEditorJS("window.cmEditor?.insertAtLineStart(`\(escapeForJS(prefix))`);")
    }

    private func insertText(_ text: String) {
        execEditorJS("window.cmEditor?.insertText(`\(escapeForJS(text))`);")
    }

    private func escapeForJS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "$", with: "\\$")
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
        UserDefaults.standard.set(focusMode, forKey: AppConstants.Keys.focusMode)
        EditorAppearanceSync.pushFocusMode()
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
        guard selectedTabID != nil else { return }
        let escapedTitle = escapeForJS(heading.title)
        execEditorJS("""
        window.cmEditor?.scrollToHeading({
            lineNumber: \(heading.lineNumber),
            title: `\(escapedTitle)`,
            level: \(heading.level)
        });
        """)
    }

    static func parseHeadings(from markdown: String) -> [HeadingItem] {
        var result: [HeadingItem] = []
        let lines = markdown.components(separatedBy: .newlines)
        var inFence = false
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inFence.toggle()
                index += 1
                continue
            }
            if inFence {
                index += 1
                continue
            }

            if Self.isLinkReferenceDefinitionLine(line) {
                index += Self.linkReferenceDefinitionConsumed(lines: lines, from: index)
                continue
            }

            if let heading = Self.parseHeadingLine(line, lineNumber: index) {
                result.append(heading)
            }
            index += 1
        }

        return result
    }

    private static func isLinkReferenceDefinitionLine(_ line: String) -> Bool {
        line.range(of: #"^\s*\[[^\]]+\]:"#, options: .regularExpression) != nil
    }

    private static func linkReferenceDefinitionConsumed(lines: [String], from start: Int) -> Int {
        guard start < lines.count, isLinkReferenceDefinitionLine(lines[start]) else { return 1 }
        var consumed = 1
        var index = start + 1
        while index < lines.count {
            let next = lines[index]
            if next.trimmingCharacters(in: .whitespaces).isEmpty { break }
            if isLinkReferenceDefinitionLine(next) { break }
            if next.range(of: #"^(#{1,6})\s+"#, options: .regularExpression) != nil { break }
            consumed += 1
            index += 1
        }
        return consumed
    }

    private static func parseHeadingLine(_ line: String, lineNumber: Int) -> HeadingItem? {
        guard let regex = try? NSRegularExpression(pattern: #"^(#{1,6})\s+(.+)$"#) else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges == 3 else { return nil }

        let level = nsLine.substring(with: match.range(at: 1)).count
        let title = nsLine.substring(with: match.range(at: 2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return HeadingItem(level: level, title: title, lineNumber: lineNumber)
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
    var bookmark: Data?
}

struct FavoriteDocumentData: Codable {
    let name: String
    let path: String
    let addedDate: Date
    var bookmark: Data?
}

struct FolderItemData: Codable {
    let name: String
    let path: String
    var bookmark: Data?
}

extension Notification.Name {
    static let showFindPanel = Notification.Name("showFindPanel")
    static let showReplacePanel = Notification.Name("showReplacePanel")
    static let editorExecJS = Notification.Name("editorExecJS")
    static let outlineHeadingsDidUpdate = Notification.Name("outlineHeadingsDidUpdate")
    static let editorHistoryContentApplied = Notification.Name("editorHistoryContentApplied")
    static let processImageFile = Notification.Name("processImageFile")
    static let readingChromeSettingsChanged = Notification.Name("readingChromeSettingsChanged")
}
