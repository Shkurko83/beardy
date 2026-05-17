import Foundation

/// Хранение и восстановление security-scoped bookmarks (App Sandbox).
enum SecurityBookmarkStore {

    private static let bookmarkPrefix = "bookmark_"

    static func saveBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: key(for: url.path))
    }

    static func bookmarkData(for path: String) -> Data? {
        UserDefaults.standard.data(forKey: key(for: path))
    }

    static func resolveURL(path: String, bookmark: Data? = nil) -> URL? {
        if let bookmark,
           let url = resolveBookmarkData(bookmark) {
            return url
        }
        if let stored = bookmarkData(for: path),
           let url = resolveBookmarkData(stored) {
            return url
        }
        let fileURL = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }

    @discardableResult
    static func resolveBookmarkData(_ data: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale, let refreshed = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(refreshed, forKey: key(for: url.path))
        }
        return url
    }

    @discardableResult
    static func beginAccess(path: String, bookmark: Data? = nil) -> URL? {
        guard let url = resolveURL(path: path, bookmark: bookmark) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    /// Runs work with security-scoped access to the document file and its parent folder (required for copying images).
    @discardableResult
    static func withDocumentFolderAccess<T>(
        documentURL: URL,
        _ work: () throws -> T
    ) throws -> T {
        let directoryURL = documentURL.deletingLastPathComponent()
        saveBookmark(for: documentURL)
        saveBookmark(for: directoryURL)

        let resolvedDoc = resolveURL(path: documentURL.path) ?? documentURL
        let resolvedDir = resolveURL(path: directoryURL.path) ?? directoryURL

        let docAccess = resolvedDoc.startAccessingSecurityScopedResource()
        let dirAccess = resolvedDir.startAccessingSecurityScopedResource()
        defer {
            if docAccess { resolvedDoc.stopAccessingSecurityScopedResource() }
            if dirAccess { resolvedDir.stopAccessingSecurityScopedResource() }
        }
        return try work()
    }

    private static func key(for path: String) -> String {
        bookmarkPrefix + path
    }
}
