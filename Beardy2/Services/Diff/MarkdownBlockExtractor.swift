import Foundation
import Markdown

enum MarkdownBlockKind: Equatable {
    case heading(Int)
    case paragraph
    case codeBlock
    case table
    case blockquote
    case list
    case thematicBreak
    case html
    case mathDisplay
}

struct MarkdownBlock: Equatable, Identifiable {
    let id: UUID
    let kind: MarkdownBlockKind
    let source: String
    let plainText: String

    var fingerprint: String {
        switch kind {
        case .table:
            if let model = TableModel.parse(source: source) {
                return "table:\(model.rowCount)x\(model.columnCount)"
            }
            return "table:\(source.hashValue)"
        case .heading(let level):
            return "h\(level):\(normalizedFingerprintSeed)"
        case .codeBlock:
            return "code:\(plainText.hashValue)"
        case .mathDisplay:
            return "math:\(source.hashValue)"
        case .thematicBreak:
            return "hr"
        case .list:
            return "list:\(normalizedFingerprintSeed)"
        case .blockquote:
            return "quote:\(normalizedFingerprintSeed)"
        case .html:
            return "html:\(source.hashValue)"
        case .paragraph:
            return "p:\(normalizedFingerprintSeed)"
        }
    }

    private var normalizedFingerprintSeed: String {
        plainText
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
            .description
    }

    /// Prose blocks that use inline word diff in Word mode.
    var isTextual: Bool {
        switch kind {
        case .paragraph, .heading, .blockquote, .list: return true
        default: return false
        }
    }
}

enum MarkdownBlockExtractor {

    static func extract(from markdown: String) -> [MarkdownBlock] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var blocks: [MarkdownBlock] = []
        let document = Document(parsing: normalized)

        for child in document.children {
            let source = sourceText(for: child, in: normalized)
            if isDisplayMathBlock(source) {
                blocks.append(MarkdownBlock(
                    id: UUID(),
                    kind: .mathDisplay,
                    source: source,
                    plainText: source
                ))
                continue
            }
            blocks.append(block(from: child, source: source))
        }

        if blocks.isEmpty {
            blocks.append(MarkdownBlock(
                id: UUID(),
                kind: .paragraph,
                source: normalized,
                plainText: normalized
            ))
        }
        return blocks
    }

    static func isDisplayMathBlock(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("$$") && t.hasSuffix("$$") && t.count > 4
    }

    /// Plain text for word diff (spacing aligned with rich diff HTML walker).
    static func plainText(fromMarkdown source: String) -> String {
        DiffPlainTextCollector.plainText(fromMarkdown: source)
    }

    private static func block(from markup: Markup, source: String) -> MarkdownBlock {
        let kind: MarkdownBlockKind
        switch markup {
        case let h as Heading: kind = .heading(h.level)
        case is CodeBlock: kind = .codeBlock
        case is Table: kind = .table
        case is BlockQuote: kind = .blockquote
        case is UnorderedList, is OrderedList: kind = .list
        case is ThematicBreak: kind = .thematicBreak
        case is HTMLBlock: kind = .html
        default: kind = .paragraph
        }
        return MarkdownBlock(
            id: UUID(),
            kind: kind,
            source: source,
            plainText: plainText(from: markup)
        )
    }

    private static func plainText(from markup: Markup) -> String {
        if let code = markup as? CodeBlock {
            return code.code
        }
        if let container = markup as? InlineContainer {
            return container.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var parts: [String] = []
        collectPlainText(from: markup, into: &parts)
        return parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collectPlainText(from markup: Markup, into parts: inout [String]) {
        for child in markup.children {
            if let text = child as? Text {
                parts.append(text.string)
            } else if let code = child as? InlineCode {
                parts.append(code.code)
            } else if child is SoftBreak || child is LineBreak {
                parts.append(" ")
            } else {
                collectPlainText(from: child, into: &parts)
            }
        }
    }

    private static func sourceText(for markup: Markup, in markdown: String) -> String {
        if let range = markup.range,
           let slice = substring(of: markdown, in: range),
           !slice.isEmpty {
            return slice
        }
        let formatted = markup.format()
        return formatted.isEmpty ? plainText(from: markup) : formatted
    }

    private static func substring(of markdown: String, in range: SourceRange) -> String? {
        guard let start = index(in: markdown, at: range.lowerBound),
              let end = index(in: markdown, at: range.upperBound),
              start < end else {
            return nil
        }
        return String(markdown[start..<end])
    }

    private static func index(in markdown: String, at location: SourceLocation) -> String.Index? {
        var lineNumber = 1
        var lineStart = markdown.startIndex
        var idx = markdown.startIndex

        while lineNumber < location.line && idx < markdown.endIndex {
            if markdown[idx] == "\n" {
                lineNumber += 1
                lineStart = markdown.index(after: idx)
            }
            idx = markdown.index(after: idx)
        }
        guard lineNumber == location.line else { return nil }

        let columnOffset = max(location.column - 1, 0)
        var utf8Remaining = columnOffset
        idx = lineStart
        while idx < markdown.endIndex && utf8Remaining > 0 {
            let next = markdown.index(after: idx)
            utf8Remaining -= markdown[idx..<next].utf8.count
            idx = next
        }
        if utf8Remaining > 0 { return markdown.endIndex }
        return idx
    }
}

// MARK: - Table model

struct TableModel: Equatable {
    let rowCount: Int
    let columnCount: Int
    let cells: [[String]]

    static func parse(source: String) -> TableModel? {
        let lines = source
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("|") }

        guard !lines.isEmpty else { return nil }

        var rows: [[String]] = []
        for line in lines {
            let stripped = line
                .replacingOccurrences(of: "|", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }

            let parts = line.split(separator: "|").map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            let cells = parts.filter { !$0.isEmpty }
            guard !cells.isEmpty else { continue }
            rows.append(cells)
        }

        guard !rows.isEmpty else { return nil }
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return nil }

        let normalized = rows.map { row -> [String] in
            var copy = row
            while copy.count < columnCount { copy.append("") }
            return Array(copy.prefix(columnCount))
        }

        return TableModel(
            rowCount: normalized.count,
            columnCount: columnCount,
            cells: normalized
        )
    }

    func hasSameShape(as other: TableModel) -> Bool {
        rowCount == other.rowCount && columnCount == other.columnCount
    }
}
