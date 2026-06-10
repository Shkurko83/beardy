import Foundation
import Markdown

/// Blockquote diff aligned per line / paragraph (not one flat word stream).
enum BlockquoteDiffRenderer {

    private struct ParsedLine {
        let plainText: String
        let bodyMarkdown: String
    }

    private enum LineAlignment {
        case equal(ParsedLine)
        case changed(old: ParsedLine, new: ParsedLine)
        case deleted(ParsedLine)
        case inserted(ParsedLine)
    }

    static func renderBlockquoteWordDiff(
        oldMarkdown: String,
        newMarkdown: String,
        documentURL: URL?
    ) -> String {
        let oldLines = parseBlockquote(oldMarkdown)
        let newLines = parseBlockquote(newMarkdown)
        guard !oldLines.isEmpty || !newLines.isEmpty else {
            return DiffMarkupRenderer.renderBlock(newMarkdown, documentURL: documentURL)
        }

        var html = "<blockquote class=\"diff-blockquote\">"
        for alignment in alignLines(old: oldLines, new: newLines) {
            switch alignment {
            case .equal(let line):
                html += "<p>\(renderLineBody(line, documentURL: documentURL))</p>\n"
            case .changed(let oldLine, let newLine):
                html += "<p>\(renderLineBodyDiff(old: oldLine, new: newLine, documentURL: documentURL))</p>\n"
            case .deleted(let line):
                html += "<p class=\"diff-blockquote-line-del\"><span class=\"diff-del\">\(DiffMarkupRenderer.escapeHTML(line.plainText))</span></p>\n"
            case .inserted(let line):
                html += "<p class=\"diff-blockquote-line-ins\"><span class=\"diff-ins\">\(DiffMarkupRenderer.escapeHTML(line.plainText))</span></p>\n"
            }
        }
        html += "</blockquote>\n"
        return html
    }

    // MARK: - Parse

    private static func parseBlockquote(_ source: String) -> [ParsedLine] {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let fromMarkers = parsePrefixedLines(trimmed)
        if !fromMarkers.isEmpty { return fromMarkers }

        let processed = trimmed
            .components(separatedBy: "\n")
            .map { $0.isEmpty ? "\u{00A0}" : $0 }
            .joined(separator: "\n")

        let document = Document(parsing: processed)
        for child in document.children {
            if let blockQuote = child as? BlockQuote {
                return lines(from: blockQuote)
            }
        }

        return [ParsedLine(plainText: plainTextFromBody(trimmed), bodyMarkdown: trimmed)]
    }

    private static func parsePrefixedLines(_ source: String) -> [ParsedLine] {
        var lines: [ParsedLine] = []
        for raw in source.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix(">") else { continue }
            var body = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            if body.isEmpty { continue }
            lines.append(
                ParsedLine(
                    plainText: plainTextFromBody(body),
                    bodyMarkdown: body
                )
            )
        }
        return lines
    }

    private static func lines(from blockQuote: BlockQuote) -> [ParsedLine] {
        var result: [ParsedLine] = []
        for child in blockQuote.children {
            if let paragraph = child as? Paragraph {
                let split = splitParagraphLines(paragraph)
                if split.isEmpty {
                    let body = paragraph.format().trimmingCharacters(in: .whitespacesAndNewlines)
                    result.append(
                        ParsedLine(
                            plainText: plainTextFromBody(body),
                            bodyMarkdown: body
                        )
                    )
                } else {
                    result.append(contentsOf: split)
                }
            } else {
                let body = child.format().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { continue }
                result.append(
                    ParsedLine(
                        plainText: plainTextFromBody(body),
                        bodyMarkdown: body
                    )
                )
            }
        }
        return result
    }

    private static func splitParagraphLines(_ paragraph: Paragraph) -> [ParsedLine] {
        var segments: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                segments.append(trimmed)
            }
            current = ""
        }

        for child in paragraph.children {
            if child is SoftBreak || child is LineBreak {
                flush()
            } else if let text = child as? Text {
                current += text.string
            } else {
                current += child.format()
            }
        }
        flush()

        return segments.map { body in
            ParsedLine(plainText: plainTextFromBody(body), bodyMarkdown: body)
        }
    }

    private static func plainTextFromBody(_ markdown: String) -> String {
        let document = Document(parsing: markdown)
        if let container = document as? InlineContainer {
            return container.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var parts: [String] = []
        for child in document.children {
            if let container = child as? InlineContainer {
                parts.append(container.plainText)
            }
        }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Align

    private static func alignLines(old: [ParsedLine], new: [ParsedLine]) -> [LineAlignment] {
        let ops = BlockDiffLCS.diff(
            old: old.map(\.plainText),
            new: new.map(\.plainText)
        )

        var result: [LineAlignment] = []
        var oldIndex = 0
        var newIndex = 0
        var opIndex = 0

        while opIndex < ops.count {
            switch ops[opIndex] {
            case .equal(let count):
                for _ in 0..<count {
                    guard oldIndex < old.count, newIndex < new.count else { break }
                    result.append(.equal(new[newIndex]))
                    oldIndex += 1
                    newIndex += 1
                }
                opIndex += 1

            case .delete(let delCount):
                if delCount == 1,
                   opIndex + 1 < ops.count,
                   case .insert(let insCount) = ops[opIndex + 1],
                   insCount == 1,
                   oldIndex < old.count,
                   newIndex < new.count {
                    result.append(.changed(old: old[oldIndex], new: new[newIndex]))
                    oldIndex += 1
                    newIndex += 1
                    opIndex += 2
                } else {
                    for _ in 0..<delCount {
                        guard oldIndex < old.count else { break }
                        result.append(.deleted(old[oldIndex]))
                        oldIndex += 1
                    }
                    opIndex += 1
                }

            case .insert(let count):
                for _ in 0..<count {
                    guard newIndex < new.count else { break }
                    result.append(.inserted(new[newIndex]))
                    newIndex += 1
                }
                opIndex += 1
            }
        }

        return result
    }

    // MARK: - Render

    private static func renderLineBody(_ line: ParsedLine, documentURL: URL?) -> String {
        renderInlineBody(line.bodyMarkdown, documentURL: documentURL)
    }

    private static func renderLineBodyDiff(
        old: ParsedLine,
        new: ParsedLine,
        documentURL: URL?
    ) -> String {
        if DiffEngine.containsRichMarkdown(old.bodyMarkdown) || DiffEngine.containsRichMarkdown(new.bodyMarkdown) {
            return DiffMarkupRenderer.renderInlineRichWordDiff(
                oldMarkdown: old.bodyMarkdown,
                newMarkdown: new.bodyMarkdown,
                highlightChangeIndex: nil,
                documentURL: documentURL
            )
        }
        return DiffMarkupRenderer.renderInlineWordDiff(
            oldText: old.plainText,
            newText: new.plainText,
            highlightChangeIndex: nil,
            documentURL: documentURL
        )
    }

    private static func renderInlineBody(_ markdown: String, documentURL: URL?) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "&nbsp;" }
        let document = Document(parsing: trimmed)
        var visitor = HTMLVisitor(documentURL: documentURL)
        var html = visitor.visit(document)
        if html.hasPrefix("<p>"), html.hasSuffix("</p>\n") {
            html = String(html.dropFirst(3).dropLast(5))
        } else if html.hasSuffix("</p>\n") {
            html = String(html.dropLast(5))
        }
        return html
    }
}
