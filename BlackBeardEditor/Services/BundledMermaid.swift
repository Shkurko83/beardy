//
//  BundledMermaid.swift
//  BlackBeardEditor
//

import Foundation

/// Локальная копия Mermaid (без CDN) — диаграммы в превью и экспорте работают офлайн.
enum BundledMermaid {
    private static let subdirectory = "Mermaid"

    static var resourceBaseURL: URL? {
        Bundle.main.resourceURL
    }

    static func scriptFileURL() -> URL? {
        Bundle.main.url(forResource: "mermaid.min", withExtension: "js", subdirectory: subdirectory)
    }

    static func loadScriptSource() -> String? {
        guard let url = scriptFileURL() else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func relativeScriptPath() -> String { "Mermaid/mermaid.min.js" }
}
