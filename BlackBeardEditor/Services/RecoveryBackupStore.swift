import Foundation
import CryptoKit

/// Unsaved recovery copies in Application Support. Removed after a successful save.
enum RecoveryBackupStore {

    struct Entry: Identifiable, Codable {
        var id: String { recoveryKey }
        let recoveryKey: String
        let documentID: UUID
        let fileName: String
        let originalPath: String?
        let savedAt: Date
    }

    private static let folderName = "Recovery"

    private static var directory: URL {
        AppConstants.App.applicationSupportDirectory()
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static func recoveryKey(for document: MarkdownDocument) -> String {
        if let path = document.url?.standardizedFileURL.path {
            let digest = SHA256.hash(data: Data(path.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        return "untitled-\(document.id.uuidString)"
    }

    static func write(document: MarkdownDocument, content: String) {
        guard AppConstants.isRecoveryBackupEnabled else { return }
        let key = recoveryKey(for: document)
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let meta = Entry(
            recoveryKey: key,
            documentID: document.id,
            fileName: document.fileName,
            originalPath: document.url?.path,
            savedAt: Date()
        )

        let contentURL = dir.appendingPathComponent("\(key).recovery.md")
        let metaURL = dir.appendingPathComponent("\(key).meta.json")

        do {
            try content.write(to: contentURL, atomically: true, encoding: .utf8)
            let data = try JSONEncoder().encode(meta)
            try data.write(to: metaURL, options: .atomic)
        } catch {
            // Best-effort recovery; ignore write failures.
        }
    }

    static func remove(document: MarkdownDocument) {
        remove(recoveryKey: recoveryKey(for: document))
    }

    static func remove(recoveryKey: String) {
        let dir = directory
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(recoveryKey).recovery.md"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(recoveryKey).meta.json"))
    }

    static func loadContent(for entry: Entry) -> String? {
        let url = directory.appendingPathComponent("\(entry.recoveryKey).recovery.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Entries whose recovery content still differs from the file on disk (or disk is missing).
    static func pendingRecoveries() -> [(entry: Entry, content: String)] {
        guard AppConstants.isRecoveryBackupEnabled else { return [] }
        let dir = directory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }

        var results: [(entry: Entry, content: String)] = []
        for metaURL in files where metaURL.pathExtension == "json" && metaURL.lastPathComponent.hasSuffix(".meta.json") {
            guard let data = try? Data(contentsOf: metaURL),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data),
                  let content = loadContent(for: entry) else { continue }

            if let path = entry.originalPath {
                let diskURL = SecurityBookmarkStore.resolveURL(path: path) ?? URL(fileURLWithPath: path)
                if let disk = try? String(contentsOf: diskURL, encoding: .utf8), disk == content {
                    remove(recoveryKey: entry.recoveryKey)
                    continue
                }
            }
            results.append((entry: entry, content: content))
        }
        return results.sorted { $0.entry.savedAt > $1.entry.savedAt }
    }
}
