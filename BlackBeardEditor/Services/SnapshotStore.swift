import AppKit
import CryptoKit
import Foundation

enum SnapshotStore {
    static let maxSnapshotsPerDocument = 50
    static let saveLabel = "Save"
    static let onOpenLabel = "On Open"

    /// In-memory history keyed by stable document path (never replaced by a smaller disk read).
    private static var sessionCache: [String: [DocumentSnapshot]] = [:]

    // MARK: - Public storage locations

    /// Sidecar next to the document: `report.md` → `report.snapshots.json`
    static func sidecarURL(for document: MarkdownDocument) -> URL? {
        guard let url = resolvedDocumentURL(for: document) else { return nil }
        return url.deletingPathExtension().appendingPathExtension("snapshots.json")
    }

    /// Always-writable library copy (survives app restart).
    static func libraryURL(for document: MarkdownDocument) -> URL {
        libraryDirectory().appendingPathComponent(libraryFileName(for: document))
    }

    static func storageURL(for document: MarkdownDocument) -> URL? {
        sidecarURL(for: document) ?? libraryURL(for: document)
    }

    // MARK: - Load / save

    static func load(for document: MarkdownDocument) -> [DocumentSnapshot] {
        let key = stableCacheKey(for: document)
        let disk = loadDiskSnapshots(for: document)
        let session = sessionCache[key] ?? []
        let merged = mergeSnapshots(disk, session)
        sessionCache[key] = merged

        if merged.count > disk.count {
            persistToDisk(merged, for: document)
        }
        return merged
    }

    @discardableResult
    static func save(_ snapshots: [DocumentSnapshot], for document: MarkdownDocument) -> Bool {
        sessionCache[stableCacheKey(for: document)] = snapshots
        return persistToDisk(snapshots, for: document)
    }

    @discardableResult
    static func append(
        content: String,
        label: String?,
        to document: MarkdownDocument,
        skipIfSameAsLatest: Bool = false,
        carryingForward existing: [DocumentSnapshot]? = nil
    ) -> [DocumentSnapshot] {
        let key = stableCacheKey(for: document)
        let disk = loadDiskSnapshots(for: document)
        let session = sessionCache[key] ?? []
        let carried = existing ?? []
        var snapshots = mergeSnapshots(disk, session, carried)

        if skipIfSameAsLatest, snapshots.first?.content == content {
            sessionCache[key] = snapshots
            return snapshots
        }
        if label == saveLabel,
           let latestSave = snapshots.first(where: { $0.label == saveLabel }),
           latestSave.content == content {
            sessionCache[key] = snapshots
            return snapshots
        }

        let snapshot = DocumentSnapshot(content: content, label: label)
        snapshots.insert(snapshot, at: 0)
        if snapshots.count > maxSnapshotsPerDocument {
            snapshots = Array(snapshots.prefix(maxSnapshotsPerDocument))
        }
        _ = save(snapshots, for: document)
        return snapshots
    }

    /// Deletes sidecar, library file, and in-memory history for this document.
    static func clearHistory(for document: MarkdownDocument) {
        let key = stableCacheKey(for: document)
        sessionCache.removeValue(forKey: key)

        if let path = document.url?.path {
            sessionCache.removeValue(forKey: path)
            sessionCache.removeValue(forKey: URL(fileURLWithPath: path).standardizedFileURL.path)
        }
        sessionCache.removeValue(forKey: "id:\(document.id.uuidString)")

        try? FileManager.default.removeItem(at: libraryURL(for: document))

        let untitledLibrary = libraryDirectory()
            .appendingPathComponent("\(document.id.uuidString).snapshots.json")
        try? FileManager.default.removeItem(at: untitledLibrary)

        if let sidecar = sidecarURL(for: document) {
            _ = withDocumentFolderAccess(for: document) {
                try? FileManager.default.removeItem(at: sidecar)
            }
        }
    }

    /// Most recent ⌘S snapshot.
    static func lastSaveSnapshot(in snapshots: [DocumentSnapshot]) -> DocumentSnapshot? {
        snapshots.first { $0.label == saveLabel }
    }

    /// Baseline for “Previous version” — newest stored version that differs from the editor.
    static func previousDifferentSnapshot(
        in snapshots: [DocumentSnapshot],
        current: String
    ) -> DocumentSnapshot? {
        let candidates = snapshots.filter { $0.label != "Unsaved" }
        if let match = candidates.first(where: { $0.content != current }) {
            return match
        }
        if candidates.count >= 2, candidates[0].content == current {
            return candidates[1]
        }
        return nil
    }

    /// Moves history from an untitled document id to a saved file path (Save As).
    static func migrateFromUntitled(documentID: UUID, to document: MarkdownDocument) {
        let oldKey = "id:\(documentID.uuidString)"
        var inherited: [DocumentSnapshot] = sessionCache[oldKey] ?? []
        let oldLibrary = libraryDirectory()
            .appendingPathComponent("\(documentID.uuidString).snapshots.json")
        if let data = try? Data(contentsOf: oldLibrary),
           let file = try? JSONDecoder().decode(SnapshotFile.self, from: data) {
            inherited.append(contentsOf: file.snapshots)
        }
        guard !inherited.isEmpty else { return }

        let merged = mergeSnapshots(load(for: document), inherited)
        sessionCache.removeValue(forKey: oldKey)
        _ = save(merged, for: document)
        try? FileManager.default.removeItem(at: oldLibrary)
    }

    static func deleteSidecar(for documentURL: URL) {
        let sidecar = documentURL.deletingPathExtension().appendingPathExtension("snapshots.json")
        _ = try? SecurityBookmarkStore.withDocumentFolderAccess(documentURL: documentURL) { _, _ in
            try? FileManager.default.removeItem(at: sidecar)
        }
        sessionCache.removeValue(forKey: documentURL.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    static func promptDeleteSidecarIfNeeded(for documentURL: URL) {
        let sidecar = documentURL.deletingPathExtension().appendingPathExtension("snapshots.json")
        let exists = (try? SecurityBookmarkStore.withDocumentFolderAccess(documentURL: documentURL) { _, _ in
            FileManager.default.fileExists(atPath: sidecar.path)
        }) ?? false
        guard exists else { return }

        let alert = NSAlert()
        alert.messageText = "Delete version history?"
        alert.informativeText = "A snapshot file exists for this document. Delete \"\(sidecar.lastPathComponent)\" as well?"
        alert.addButton(withTitle: "Delete Snapshots")
        alert.addButton(withTitle: "Keep Snapshots")
        if alert.runModal() == .alertFirstButtonReturn {
            deleteSidecar(for: documentURL)
        }
    }

    // MARK: - Internals

    private static func libraryDirectory() -> URL {
        let dir = AppConstants.App.applicationSupportDirectory()
            .appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func libraryFileName(for document: MarkdownDocument) -> String {
        if let path = stableDocumentPath(for: document) {
            let digest = SHA256.hash(data: Data(path.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            return "\(hex).snapshots.json"
        }
        return "\(document.id.uuidString).snapshots.json"
    }

    private static func stableDocumentPath(for document: MarkdownDocument) -> String? {
        guard let url = document.url else { return nil }
        let resolved = SecurityBookmarkStore.resolveURL(path: url.path) ?? url
        return resolved.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func stableCacheKey(for document: MarkdownDocument) -> String {
        if let path = stableDocumentPath(for: document) {
            return path
        }
        return "id:\(document.id.uuidString)"
    }

    private static func resolvedDocumentURL(for document: MarkdownDocument) -> URL? {
        guard let url = document.url else { return nil }
        return SecurityBookmarkStore.resolveURL(path: url.path) ?? url.standardizedFileURL
    }

    private static func loadDiskSnapshots(for document: MarkdownDocument) -> [DocumentSnapshot] {
        let sidecar = sidecarURL(for: document)
            .flatMap { readSnapshots(from: $0, document: document, label: "sidecar") } ?? []
        let library = readSnapshots(
            from: libraryURL(for: document),
            document: document,
            label: "library"
        ) ?? []
        return mergeSnapshots(sidecar, library)
    }

    private static func mergeSnapshots(_ sources: [DocumentSnapshot]...) -> [DocumentSnapshot] {
        var byID: [UUID: DocumentSnapshot] = [:]
        for snapshot in sources.flatMap({ $0 }) {
            byID[snapshot.id] = snapshot
        }
        return byID.values.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    private static func persistToDisk(_ snapshots: [DocumentSnapshot], for document: MarkdownDocument) -> Bool {
        let path = stableDocumentPath(for: document) ?? document.id.uuidString
        let file = SnapshotFile(documentPath: path, snapshots: snapshots)
        guard let data = try? JSONEncoder().encode(file) else {
            NSLog("SnapshotStore: failed to encode snapshots for \(path)")
            return false
        }

        let libraryOK = writeData(data, to: libraryURL(for: document), document: document, label: "library")
        let sidecarOK = writeDataToSidecar(data, document: document)

        if libraryOK || sidecarOK {
            NSLog(
                "SnapshotStore: persisted \(snapshots.count) snapshot(s) for \(path) (library=\(libraryOK), sidecar=\(sidecarOK))"
            )
            return true
        }
        NSLog("SnapshotStore: failed to persist snapshots for \(path)")
        return false
    }

    private static func readSnapshots(
        from fileURL: URL,
        document: MarkdownDocument,
        label: String
    ) -> [DocumentSnapshot]? {
        let read: () -> [DocumentSnapshot]? = {
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let file = try? JSONDecoder().decode(SnapshotFile.self, from: data) else {
                return nil
            }
            return file.snapshots.sorted { $0.createdAt > $1.createdAt }
        }

        if fileURL.standardizedFileURL == libraryURL(for: document).standardizedFileURL {
            return read()
        }
        return withDocumentFolderAccess(for: document, read)
    }

    @discardableResult
    private static func writeData(
        _ data: Data,
        to fileURL: URL,
        document: MarkdownDocument,
        label: String
    ) -> Bool {
        let write: () -> Bool = {
            do {
                let parent = fileURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: parent.path) {
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                try data.write(to: fileURL, options: .atomic)
                return true
            } catch {
                NSLog("SnapshotStore: \(label) write failed at \(fileURL.path): \(error.localizedDescription)")
                return false
            }
        }

        if fileURL.standardizedFileURL == libraryURL(for: document).standardizedFileURL {
            return write()
        }
        return withDocumentFolderAccess(for: document, write)
    }

    @discardableResult
    private static func writeDataToSidecar(_ data: Data, document: MarkdownDocument) -> Bool {
        guard let sidecar = sidecarURL(for: document) else { return false }
        return writeData(data, to: sidecar, document: document, label: "sidecar")
    }

    private static func withDocumentFolderAccess<T>(for document: MarkdownDocument, _ work: () -> T) -> T {
        guard let url = resolvedDocumentURL(for: document) else { return work() }
        if let result = try? SecurityBookmarkStore.withDocumentFolderAccess(documentURL: url) { _, _ in work() } {
            return result
        }
        return work()
    }
}
