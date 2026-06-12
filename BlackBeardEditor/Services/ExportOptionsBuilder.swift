import Foundation

/// Builds `ExportService.ExportOptions` from user defaults.
enum ExportOptionsBuilder {

    static func make(for format: ExportService.ExportFormat) -> ExportService.ExportOptions {
        var options = ExportService.ExportOptions()
        options.pdfMargins = resolvedPDFMargins()
        options.paperSize = resolvedPaperSize()
        options.includePageNumbers = AppConstants.boolSetting(
            forKey: AppConstants.Keys.exportPDFIncludePageNumbers,
            default: false
        )
        options.includeTOC = AppConstants.boolSetting(
            forKey: AppConstants.Keys.exportPDFIncludeTOC,
            default: false
        )
        options.includeThemeBackground = AppConstants.boolSetting(
            forKey: AppConstants.Keys.exportPDFIncludeThemeBackground,
            default: false
        )
        options.htmlStandalone = AppConstants.boolSetting(
            forKey: AppConstants.Keys.exportHTMLStandalone,
            default: true
        )
        options.removeYAMLFrontmatter = AppConstants.boolSetting(
            forKey: AppConstants.Keys.exportRemoveYAMLFrontmatter,
            default: false
        )
        options.preserveEmptyLines = AppConstants.boolSetting(
            forKey: AppConstants.Keys.exportPreserveEmptyLines,
            default: true
        )
        options.includeCSS = format.includesStyles
        return options
    }

    static func prepareMarkdown(_ markdown: String, options: ExportService.ExportOptions) -> String {
        options.removeYAMLFrontmatter ? markdown.removingYAMLFrontmatter : markdown
    }

    private static func resolvedPDFMargins() -> ExportService.ExportOptions.PDFMargins {
        let legacy = UserDefaults.standard.double(forKey: AppConstants.Keys.exportPDFMargins)
        let fallback = legacy >= 18 ? legacy : Double(AppConstants.Export.defaultPDFMargins)

        func side(_ key: String) -> CGFloat {
            if UserDefaults.standard.object(forKey: key) != nil {
                let value = UserDefaults.standard.double(forKey: key)
                return CGFloat(min(max(value, 18), 144))
            }
            return CGFloat(fallback)
        }

        return ExportService.ExportOptions.PDFMargins(
            top: side(AppConstants.Keys.exportPDFMarginTop),
            bottom: side(AppConstants.Keys.exportPDFMarginBottom),
            left: side(AppConstants.Keys.exportPDFMarginLeft),
            right: side(AppConstants.Keys.exportPDFMarginRight)
        )
    }

    private static func resolvedPaperSize() -> ExportService.ExportOptions.PaperSize {
        let raw = UserDefaults.standard.string(forKey: AppConstants.Keys.exportPDFPaperSize) ?? "letter"
        switch raw.lowercased() {
        case "a4": return .a4
        case "legal": return .legal
        default: return .letter
        }
    }
}
