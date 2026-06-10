import Foundation

/// Persists open editor tabs between launches.
enum SessionStore {

    struct SavedTab: Codable {
        let id: UUID
        let path: String?
        let fileName: String
        let untitledContent: String?
    }

    struct SavedSession: Codable {
        let tabs: [SavedTab]
        let selectedTabID: UUID?
        let savedAt: Date
    }

    private static let fileName = "window-session.json"

    private static var fileURL: URL {
        AppConstants.App.applicationSupportDirectory()
            .appendingPathComponent(fileName)
    }

    static func save(tabs: [EditorTab], selectedTabID: UUID?) {
        guard AppConstants.restoreOpenFilesOnLaunch else {
            clear()
            return
        }

        let saved = SavedSession(
            tabs: tabs.map { tab in
                SavedTab(
                    id: tab.id,
                    path: tab.document.url?.path,
                    fileName: tab.document.fileName,
                    untitledContent: tab.document.url == nil ? tab.document.content : nil
                )
            },
            selectedTabID: selectedTabID,
            savedAt: Date()
        )

        do {
            let data = try JSONEncoder().encode(saved)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort session persistence.
        }
    }

    static func load() -> SavedSession? {
        guard AppConstants.restoreOpenFilesOnLaunch,
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data),
              !session.tabs.isEmpty else {
            return nil
        }
        return session
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
