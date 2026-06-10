//
//  BundledHighlightJS.swift
//  BlackBeardEditor
//

import Foundation

/// Локальные копии highlight.js (без CDN) — редактор и экспорт работают офлайн.
enum BundledHighlightJS {
    private static let subdirectory = "HighlightJS"
    private static let stylesSubdirectory = "HighlightJS/styles"

    static var resourceBaseURL: URL? {
        Bundle.main.resourceURL
    }

    static func scriptFileURL() -> URL? {
        Bundle.main.url(forResource: "highlight.min", withExtension: "js", subdirectory: subdirectory)
    }

    static func lineNumbersScriptFileURL() -> URL? {
        Bundle.main.url(
            forResource: "highlightjs-line-numbers.min",
            withExtension: "js",
            subdirectory: subdirectory
        )
    }

    static func themeCSSFileURL(for theme: CodeTheme) -> URL? {
        Bundle.main.url(
            forResource: "\(theme.rawValue).min",
            withExtension: "css",
            subdirectory: stylesSubdirectory
        )
    }

    static func themeCSSFileURLString(for theme: CodeTheme) -> String {
        themeCSSFileURL(for: theme)?.absoluteString ?? ""
    }

    static func loadScriptSource() -> String? {
        guard let url = scriptFileURL() else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func loadLineNumbersScriptSource() -> String? {
        guard let url = lineNumbersScriptFileURL() else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func loadThemeCSS(for theme: CodeTheme) -> String? {
        guard let url = themeCSSFileURL(for: theme) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Относительный путь от `codemirror-editor.html` в бандле.
    static func relativeScriptPath() -> String { "HighlightJS/highlight.min.js" }

    static func relativeLineNumbersPath() -> String { "HighlightJS/highlightjs-line-numbers.min.js" }

    static func relativeThemeCSSPath(for theme: CodeTheme) -> String {
        "HighlightJS/styles/\(theme.rawValue).min.css"
    }
}
