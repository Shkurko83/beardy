import Foundation

/// Держит security-scoped доступ к активному документу (App Sandbox).
enum DocumentSecurityAccess {
    private static var activeDocumentURL: URL?

    static func activate(document url: URL) {
        deactivate()
        if SecurityBookmarkStore.beginAccess(path: url.path) != nil
            || url.startAccessingSecurityScopedResource() {
            activeDocumentURL = url
        }
        SecurityBookmarkStore.saveBookmark(for: url)
        SecurityBookmarkStore.saveBookmark(for: url.deletingLastPathComponent())
    }

    static func deactivate() {
        activeDocumentURL?.stopAccessingSecurityScopedResource()
        activeDocumentURL = nil
    }
}
