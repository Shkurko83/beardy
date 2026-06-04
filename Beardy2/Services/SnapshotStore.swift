import AppKit
import Foundation

enum SnapshotStore {
    static let maxSnapshotsPerDocument = 50
    static let saveLabel = "Save"
    static let onOpenLabel = "On Open"

    static func storageURL(for document: MarkdownDocument) -> URL? {
        if let url = document.url {
            return url.deletingPathExtension().appendingPathExtension("snapshots.json")
        }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Beardy2/snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(document.id.uuidString).snapshots.json")
    }

    static func load(for document: MarkdownDocument) -> [DocumentSnapshot] {
        guard let fileURL = storageURL(for: document) else { return [] }
        let access = beginAccess(for: document)
        defer { endAccess(access) }

        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(SnapshotFile.self, from: data) else {
            return []
        }
        return file.snapshots.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    static func save(_ snapshots: [DocumentSnapshot], for document: MarkdownDocument) -> Bool {
        guard let fileURL = storageURL(for: document) else { return false }
        let path = document.url?.path ?? document.id.uuidString
        let file = SnapshotFile(documentPath: path, snapshots: snapshots)
        guard let data = try? JSONEncoder().encode(file) else { return false }

        let access = beginAccess(for: document)
        defer { endAccess(access) }
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
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
        // Editor matches the latest save; compare against the prior save in history.
        if candidates.count >= 2, candidates[0].content == current {
            return candidates[1]
        }
        return nil
    }

    @discardableResult
    static func append(
        content: String,
        label: String?,
        to document: MarkdownDocument,
        skipIfSameAsLatest: Bool = false
    ) -> [DocumentSnapshot] {
        var snapshots = load(for: document)
        if skipIfSameAsLatest, snapshots.first?.content == content {
            return snapshots
        }
        let snapshot = DocumentSnapshot(content: content, label: label)
        snapshots.insert(snapshot, at: 0)
        if snapshots.count > maxSnapshotsPerDocument {
            snapshots = Array(snapshots.prefix(maxSnapshotsPerDocument))
        }
        _ = save(snapshots, for: document)
        return load(for: document)
    }

    static func deleteSidecar(for documentURL: URL) {
        let sidecar = documentURL.deletingPathExtension().appendingPathExtension("snapshots.json")
        try? FileManager.default.removeItem(at: sidecar)
    }

    static func promptDeleteSidecarIfNeeded(for documentURL: URL) {
        let sidecar = documentURL.deletingPathExtension().appendingPathExtension("snapshots.json")
        guard FileManager.default.fileExists(atPath: sidecar.path) else { return }

        let alert = NSAlert()
        alert.messageText = "Delete version history?"
        alert.informativeText = "A snapshot file exists for this document. Delete \"\(sidecar.lastPathComponent)\" as well?"
        alert.addButton(withTitle: "Delete Snapshots")
        alert.addButton(withTitle: "Keep Snapshots")
        if alert.runModal() == .alertFirstButtonReturn {
            try? FileManager.default.removeItem(at: sidecar)
        }
    }

    // MARK: - Security-scoped access

    private struct FileAccess {
        let fileURL: URL?
        let directoryURL: URL?
        let holdsFile: Bool
        let holdsDirectory: Bool
    }

    private static func beginAccess(for document: MarkdownDocument) -> FileAccess? {
        guard let fileURL = document.url else { return nil }
        let directoryURL = fileURL.deletingLastPathComponent()
        let holdsDirectory = SecurityBookmarkStore.beginAccess(path: directoryURL.path) != nil
            || directoryURL.startAccessingSecurityScopedResource()
        let holdsFile = SecurityBookmarkStore.beginAccess(path: fileURL.path) != nil
            || fileURL.startAccessingSecurityScopedResource()
        return FileAccess(
            fileURL: fileURL,
            directoryURL: directoryURL,
            holdsFile: holdsFile,
            holdsDirectory: holdsDirectory
        )
    }

    private static func endAccess(_ access: FileAccess?) {
        guard let access else { return }
        if access.holdsFile, let fileURL = access.fileURL {
            fileURL.stopAccessingSecurityScopedResource()
        }
        if access.holdsDirectory, let directoryURL = access.directoryURL {
            directoryURL.stopAccessingSecurityScopedResource()
        }
    }
}
