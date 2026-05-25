//
//  BundledKaTeX.swift
//  Beardy2
//

import Foundation

/// Локальная копия KaTeX (без CDN) — формулы в превью и экспорте работают офлайн.
enum BundledKaTeX {
    private static let subdirectory = "KaTeX"

    static var resourceBaseURL: URL? {
        Bundle.main.resourceURL
    }

    static func scriptFileURL() -> URL? {
        Bundle.main.url(forResource: "katex.min", withExtension: "js", subdirectory: subdirectory)
    }

    static func cssFileURL() -> URL? {
        Bundle.main.url(forResource: "katex.min", withExtension: "css", subdirectory: subdirectory)
    }

    static func loadScriptSource() -> String? {
        guard let url = scriptFileURL() else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func loadCSS() -> String? {
        guard let url = cssFileURL() else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func relativeScriptPath() -> String { "KaTeX/katex.min.js" }

    static func relativeCSSPath() -> String { "KaTeX/katex.min.css" }
}
