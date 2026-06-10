import AppKit
import Foundation
import CryptoKit

/// Security-scoped bookmarks stored on disk (not UserDefaults — macOS limits prefs to ~4 MB).
enum SecurityBookmarkStore {

    enum FolderAccessError: LocalizedError {
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Permission denied for the document folder — save the document again or re-open it from Finder"
            }
        }
    }

    private static let legacyBookmarkPrefix = "bookmark_"
    private static let storeFileName = "security-bookmarks.plist"
    private static var memoryCache: [String: Data]?
    private static var didMigrateFromUserDefaults = false
    private static let lock = NSLock()

    private static let ignoredPathMarkers = [
        "/node_modules/",
        "/site-packages/",
        "/venv/",
        "/.venv/",
        "/.git/",
        "/deriveddata/",
        "/pods/",
        "/.build/",
        "/__pycache__/",
    ]

    static func saveBookmark(for url: URL) {
        let path = url.path
        guard !isIgnoredBookmarkPath(path) else { return }
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        storeBookmark(data, for: path)
    }

    static func bookmarkData(for path: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        migrateFromUserDefaultsIfNeeded()
        return loadStore()[path]
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
            storeBookmark(refreshed, for: url.path)
        }
        return url
    }

    @discardableResult
    static func beginAccess(path: String, bookmark: Data? = nil) -> URL? {
        guard let url = resolveURL(path: path, bookmark: bookmark) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    /// Resolved document + parent folder URLs with security-scoped bookmarks when available.
    static func resolvedDocumentContext(for documentURL: URL) -> (document: URL, folder: URL) {
        let standardized = documentURL.standardizedFileURL
        let folderPath = standardized.deletingLastPathComponent().path
        let resolvedDoc = resolveURL(path: standardized.path) ?? standardized
        let resolvedDir = resolveURL(path: folderPath) ?? resolvedDoc.deletingLastPathComponent()
        return (resolvedDoc, resolvedDir)
    }

    /// Ask the user to grant write access to the folder that contains the document (sandbox).
    @discardableResult
    static func requestFolderAccess(containing documentURL: URL) -> URL? {
        let context = resolvedDocumentContext(for: documentURL)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Grant Access"
        panel.message = "Black Beard Editor needs access to this folder to save images next to your document."
        panel.directoryURL = context.folder

        guard panel.runModal() == .OK, let chosen = panel.url else { return nil }

        let accessed = chosen.startAccessingSecurityScopedResource()
        defer {
            if accessed { chosen.stopAccessingSecurityScopedResource() }
        }
        saveBookmark(for: chosen)
        return resolveURL(path: chosen.path) ?? chosen.standardizedFileURL
    }

    /// Runs work with security-scoped access to the document file and its parent folder (required for copying images).
    @discardableResult
    static func withDocumentFolderAccess<T>(
        documentURL: URL,
        _ work: (URL, URL) throws -> T
    ) throws -> T {
        let context = resolvedDocumentContext(for: documentURL)
        saveBookmark(for: context.document)
        saveBookmark(for: context.folder)

        let docAccess = context.document.startAccessingSecurityScopedResource()
        let dirAccess = context.folder.startAccessingSecurityScopedResource()
        defer {
            if docAccess { context.document.stopAccessingSecurityScopedResource() }
            if dirAccess { context.folder.stopAccessingSecurityScopedResource() }
        }

        guard dirAccess else {
            throw FolderAccessError.permissionDenied
        }
        return try work(context.document, context.folder)
    }

    static func embeddedAssetsDirectory(for documentURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(documentURL.standardizedFileURL.path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let dir = AppConstants.App.applicationSupportDirectory()
            .appendingPathComponent("EmbeddedImages", isDirectory: true)
            .appendingPathComponent(hex, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes legacy `bookmark_*` keys from UserDefaults (one-time, also drops junk paths).
    static func performStartupMaintenance() {
        lock.lock()
        defer { lock.unlock() }
        migrateFromUserDefaultsIfNeeded()
    }

    // MARK: - Private

    private static func storeBookmark(_ data: Data, for path: String) {
        lock.lock()
        defer { lock.unlock() }
        migrateFromUserDefaultsIfNeeded()
        var store = loadStore()
        store[path] = data
        persistStore(store)
    }

    private static var storeURL: URL {
        AppConstants.App.applicationSupportDirectory()
            .appendingPathComponent(storeFileName)
    }

    private static func loadStore() -> [String: Data] {
        if let memoryCache { return memoryCache }
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL),
              let decoded = try? PropertyListDecoder().decode([String: Data].self, from: data) else {
            memoryCache = [:]
            return [:]
        }
        memoryCache = decoded
        return decoded
    }

    private static func persistStore(_ store: [String: Data]) {
        memoryCache = store
        guard let data = try? PropertyListEncoder().encode(store) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private static func migrateFromUserDefaultsIfNeeded() {
        guard !didMigrateFromUserDefaults else { return }
        didMigrateFromUserDefaults = true

        var store = loadStore()
        let defaults = UserDefaults.standard
        for (key, value) in defaults.dictionaryRepresentation() {
            guard key.hasPrefix(legacyBookmarkPrefix), let data = value as? Data else { continue }
            let path = String(key.dropFirst(legacyBookmarkPrefix.count))
            if !isIgnoredBookmarkPath(path) {
                store[path] = data
            }
            defaults.removeObject(forKey: key)
        }
        persistStore(store)
    }

    static func isIgnoredBookmarkPath(_ path: String) -> Bool {
        let lowered = path.lowercased()
        return ignoredPathMarkers.contains { lowered.contains($0) }
    }

    static func shouldSkipFolderName(_ name: String) -> Bool {
        switch name.lowercased() {
        case "node_modules", "venv", ".venv", "site-packages", "pods", "deriveddata",
             ".build", "__pycache__", "build", "dist", "vendor", "carthage":
            return true
        default:
            return false
        }
    }
}
