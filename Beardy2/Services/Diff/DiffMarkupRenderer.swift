import Foundation
import Markdown

/// Renders markdown blocks and inline diff markup to HTML.
enum DiffMarkupRenderer {

    static func renderBlock(_ source: String, documentURL: URL?) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if MarkdownBlockExtractor.isDisplayMathBlock(trimmed) {
            return renderMathDisplayHTML(trimmed)
        }

        // Swift Markdown flattens nested ordered lists; use indentation-aware parser instead.
        if let listHTML = ListDiffRenderer.renderListPreservingNesting(trimmed, documentURL: documentURL) {
            return listHTML
        }

        let processed = trimmed.components(separatedBy: "\n")
            .map { $0.isEmpty ? "\u{00A0}" : $0 }
            .joined(separator: "\n")

        let document = Document(parsing: processed)
        var visitor = HTMLVisitor(documentURL: documentURL)
        return visitor.visit(document)
    }

    static func renderInlineWordDiff(
        oldText: String,
        newText: String,
        highlightChangeIndex: Int? = nil,
        documentURL: URL?
    ) -> String {
        let oldWords = tokenize(oldText)
        let newWords = tokenize(newText)
        let ops = DiffLCS.diff(old: oldWords, new: newWords)
        var parts: [String] = []
        var index = 0

        while index < ops.count {
            switch ops[index] {
            case .equal(let words):
                parts.append(escapeHTML(words.joined(separator: " ")))
                index += 1

            case .delete(let deleted):
                var inserted: [String] = []
                if index + 1 < ops.count, case .insert(let words) = ops[index + 1] {
                    inserted = words
                    index += 2
                } else {
                    index += 1
                }
                let delText = escapeHTML(deleted.joined(separator: " "))
                let insText = escapeHTML(inserted.joined(separator: " "))
                if !deleted.isEmpty {
                    parts.append(span(className: "diff-del", changeIndex: highlightChangeIndex, inner: delText))
                }
                if !inserted.isEmpty {
                    parts.append(span(className: "diff-ins", changeIndex: highlightChangeIndex, inner: insText))
                }

            case .insert(let words):
                let insText = escapeHTML(words.joined(separator: " "))
                parts.append(span(className: "diff-ins", changeIndex: highlightChangeIndex, inner: insText))
                index += 1
            }
        }

        return parts.joined(separator: " ")
    }

    static func span(className: String, changeIndex: Int?, inner: String) -> String {
        let idx = changeIndex.map { " data-change-index=\"\($0)\"" } ?? ""
        return "<span class=\"\(className)\"\(idx)>\(inner)</span>"
    }

    static func renderTableCellDiff(
        oldModel: TableModel,
        newModel: TableModel,
        documentURL: URL?,
        changeIndex: inout Int
    ) -> (html: String, firstChangeIndex: Int?) {
        var firstChangeIndex: Int?
        var html = "<table class=\"diff-table\"><thead><tr>"

        for col in 0..<newModel.columnCount {
            let oldCell = oldModel.cells[0][col]
            let newCell = newModel.cells[0][col]
            let cellHTML = renderCellPair(
                old: oldCell,
                new: newCell,
                documentURL: documentURL,
                changeIndex: &changeIndex,
                firstChangeIndex: &firstChangeIndex
            )
            html += "<th>\(cellHTML)</th>"
        }
        html += "</tr></thead><tbody>"

        for row in 1..<newModel.rowCount {
            html += "<tr>"
            for col in 0..<newModel.columnCount {
                let oldCell = row < oldModel.rowCount ? oldModel.cells[row][col] : ""
                let newCell = newModel.cells[row][col]
                let cellHTML = renderCellPair(
                    old: oldCell,
                    new: newCell,
                    documentURL: documentURL,
                    changeIndex: &changeIndex,
                    firstChangeIndex: &firstChangeIndex
                )
                html += "<td>\(cellHTML)</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>"
        return (html, firstChangeIndex)
    }

    private static func renderCellPair(
        old: String,
        new: String,
        documentURL: URL?,
        changeIndex: inout Int,
        firstChangeIndex: inout Int?
    ) -> String {
        if old == new {
            return renderInlineSnippet(new, documentURL: documentURL)
        }
        changeIndex += 1
        if firstChangeIndex == nil { firstChangeIndex = changeIndex }
        let idx = changeIndex
        let inner: String
        if DiffEngine.containsRichMarkdown(old) || DiffEngine.containsRichMarkdown(new) {
            inner = renderInlineRichWordDiff(
                oldMarkdown: old,
                newMarkdown: new,
                highlightChangeIndex: idx,
                documentURL: documentURL
            )
        } else {
            inner = renderInlineWordDiff(
                oldText: old,
                newText: new,
                highlightChangeIndex: idx,
                documentURL: documentURL
            )
        }
        return "<span class=\"diff-cell-change\" data-change-index=\"\(idx)\">\(inner)</span>"
    }

    static func renderInlineSnippet(_ markdown: String, documentURL: URL?) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "&nbsp;" }
        let document = Document(parsing: trimmed)
        var visitor = HTMLVisitor(documentURL: documentURL)
        var html = visitor.visit(document)
        if html.hasPrefix("<p>"), html.hasSuffix("</p>\n") {
            html = String(html.dropFirst(3).dropLast(5))
        }
        return html
    }

    /// Blockquote with per-line alignment and word diff inside each `<p>`.
    static func renderBlockquoteWordDiff(
        oldMarkdown: String,
        newMarkdown: String,
        documentURL: URL?
    ) -> String {
        BlockquoteDiffRenderer.renderBlockquoteWordDiff(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown,
            documentURL: documentURL
        )
    }

    /// Lists with per-item alignment and word diff inside `<li>`.
    static func renderListWordDiff(
        oldMarkdown: String,
        newMarkdown: String,
        documentURL: URL?
    ) -> String {
        ListDiffRenderer.renderListWordDiff(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown,
            documentURL: documentURL
        )
    }

    static func renderInlineRichWordDiff(
        oldMarkdown: String,
        newMarkdown: String,
        highlightChangeIndex: Int? = nil,
        documentURL: URL?
    ) -> String {
        let oldPlain = DiffPlainTextCollector.plainText(fromMarkdown: oldMarkdown)
        let newPlain = DiffPlainTextCollector.plainText(fromMarkdown: newMarkdown)
        let segments = wordDiffSegments(old: oldPlain, new: newPlain)
        guard let document = DiffPlainTextCollector.parseDocument(newMarkdown) else { return "" }
        var walker = RichWordDiffHTMLWalker(
            segments: segments,
            highlightChangeIndex: highlightChangeIndex
        )
        return walker.visit(document)
    }

    fileprivate struct PlainSegment {
        enum Kind { case equal, deleted, inserted }
        let kind: Kind
        let text: String
    }

    private static func wordDiffSegments(old: String, new: String) -> [PlainSegment] {
        let oldWords = tokenize(old)
        let newWords = tokenize(new)
        let ops = DiffLCS.diff(old: oldWords, new: newWords)
        var segments: [PlainSegment] = []
        for op in ops {
            switch op {
            case .equal(let words):
                for word in words {
                    segments.append(PlainSegment(kind: .equal, text: word))
                }
            case .delete(let words):
                for word in words {
                    segments.append(PlainSegment(kind: .deleted, text: word))
                }
            case .insert(let words):
                for word in words {
                    segments.append(PlainSegment(kind: .inserted, text: word))
                }
            }
        }
        return segments
    }

    private static func renderMathDisplayHTML(_ source: String) -> String {
        let latex = MathBlockNormalizer.displayLatex(from: source)
        let escaped = escapeHTML(latex)
        return "<div class=\"math-display\" data-latex=\"\(escaped)\">\(escaped)</div>"
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Rich inline word diff (preserves links, emphasis)

private struct RichWordDiffHTMLWalker: MarkupVisitor {
    typealias Result = String

    private var segments: [DiffMarkupRenderer.PlainSegment]
    private var segmentIndex = 0
    private let highlightChangeIndex: Int?
    private var insideBlockQuote = false
    private var insideListItem = false

    init(
        segments: [DiffMarkupRenderer.PlainSegment],
        highlightChangeIndex: Int? = nil
    ) {
        self.segments = segments
        self.highlightChangeIndex = highlightChangeIndex
    }

    mutating func defaultVisit(_ markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        "<h\(heading.level) class=\"diff-inline-text\">\(joinInlineChildren(heading))</h\(heading.level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let inner = joinInlineChildren(paragraph)
        if insideListItem {
            return inner
        }
        if insideBlockQuote {
            return "<p>\(inner)</p>\n"
        }
        return "<p class=\"diff-inline-text\">\(inner)</p>\n"
    }

    private mutating func joinInlineChildren(_ markup: Markup) -> String {
        var parts: [String] = []
        for child in markup.children {
            let part = visit(child)
            guard !part.isEmpty else { continue }
            if let last = parts.last, needsSpaceBetween(last, part) {
                parts.append(" ")
            }
            parts.append(part)
        }
        return parts.joined()
    }

    private func needsSpaceBetween(_ left: String, _ right: String) -> Bool {
        guard let last = left.last, let first = right.first else { return false }
        return !last.isWhitespace && !first.isWhitespace
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> String {
        let isTaskList = list.children.contains { ($0 as? ListItem)?.checkbox != nil }
        let extra = isTaskList ? " task-list" : ""
        return "<ul class=\"diff-list\(extra)\">\(defaultVisit(list))</ul>\n"
    }

    mutating func visitOrderedList(_ list: OrderedList) -> String {
        "<ol class=\"diff-list\">\(defaultVisit(list))</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        let wasInside = insideListItem
        insideListItem = true
        var inner = ""
        for child in listItem.children {
            let part = visit(child)
            if !part.isEmpty, !inner.isEmpty, needsSpaceBetween(inner, part) {
                inner += " "
            }
            inner += part
        }
        insideListItem = wasInside
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? "checked " : ""
            return "<li class=\"task-list-item\"><input type=\"checkbox\" class=\"diff-task-checkbox\" \(checked)disabled> \(inner)</li>\n"
        }
        return "<li>\(inner)</li>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let wasInside = insideBlockQuote
        insideBlockQuote = true
        let inner = defaultVisit(blockQuote)
        insideBlockQuote = wasInside
        return "<blockquote class=\"diff-blockquote\">\(inner)</blockquote>\n"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(joinInlineChildren(strong))</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(joinInlineChildren(emphasis))</em>"
    }

    mutating func visitLink(_ link: Markdown.Link) -> String {
        let href = DiffMarkupRenderer.escapeHTML(link.destination ?? "")
        return "<a href=\"\(href)\" target=\"_blank\" rel=\"noopener noreferrer\">\(joinInlineChildren(link))</a>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(emitTextWords(inlineCode.code))</code>"
    }

    mutating func visitText(_ text: Text) -> String {
        emitTextWords(text.string)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { " " }
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { " " }

    private mutating func emitTextWords(_ string: String) -> String {
        let words = string.split(whereSeparator: \.isWhitespace).map(String.init)
        var html = ""
        var needsLeadingSpace = false

        for word in words {
            emitPendingDeletes(needsLeadingSpace: &needsLeadingSpace, into: &html)
            guard segmentIndex < segments.count else {
                appendPlainWord(word, needsLeadingSpace: &needsLeadingSpace, into: &html)
                continue
            }
            if needsLeadingSpace { html += " " }
            let segment = segments[segmentIndex]
            html += wrapSegment(segment, forcedText: word)
            segmentIndex += 1
            needsLeadingSpace = true
        }
        emitPendingDeletes(needsLeadingSpace: &needsLeadingSpace, into: &html)
        return html
    }

    private mutating func emitPendingDeletes(needsLeadingSpace: inout Bool, into html: inout String) {
        var deleted: [String] = []
        while segmentIndex < segments.count, segments[segmentIndex].kind == .deleted {
            deleted.append(segments[segmentIndex].text)
            segmentIndex += 1
        }
        guard !deleted.isEmpty else { return }
        if needsLeadingSpace { html += " " }
        let inner = DiffMarkupRenderer.escapeHTML(deleted.joined(separator: " "))
        html += DiffMarkupRenderer.span(
            className: "diff-del",
            changeIndex: highlightChangeIndex,
            inner: inner
        )
        needsLeadingSpace = true
    }

    private func appendPlainWord(_ word: String, needsLeadingSpace: inout Bool, into html: inout String) {
        if needsLeadingSpace { html += " " }
        html += DiffMarkupRenderer.escapeHTML(word)
        needsLeadingSpace = true
    }

    private func wrapSegment(
        _ segment: DiffMarkupRenderer.PlainSegment,
        forcedText: String
    ) -> String {
        let text = DiffMarkupRenderer.escapeHTML(forcedText)
        switch segment.kind {
        case .equal:
            return text
        case .deleted:
            return DiffMarkupRenderer.span(
                className: "diff-del",
                changeIndex: highlightChangeIndex,
                inner: text
            )
        case .inserted:
            return DiffMarkupRenderer.span(
                className: "diff-ins",
                changeIndex: highlightChangeIndex,
                inner: text
            )
        }
    }
}

// MARK: - LCS helper shared by diff

enum DiffLCS {
    enum Op {
        case equal([String])
        case delete([String])
        case insert([String])
    }

    static func diff(old: [String], new: [String]) -> [Op] {
        if old.isEmpty { return new.isEmpty ? [] : [.insert(new)] }
        if new.isEmpty { return [.delete(old)] }

        let n = old.count, m = new.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if old[i - 1] == new[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var ops: [Op] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, old[i - 1] == new[j - 1] {
                ops.append(.equal([old[i - 1]]))
                i -= 1; j -= 1
            } else if j > 0, (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                ops.append(.insert([new[j - 1]]))
                j -= 1
            } else {
                ops.append(.delete([old[i - 1]]))
                i -= 1
            }
        }

        return ops.reversed().reduce(into: [Op]()) { result, op in
            merge(&result, op)
        }
    }

    private static func merge(_ result: inout [Op], _ op: Op) {
        guard let last = result.last else {
            result.append(op)
            return
        }
        switch (last, op) {
        case (.equal(let a), .equal(let b)): result[result.count - 1] = .equal(a + b)
        case (.delete(let a), .delete(let b)): result[result.count - 1] = .delete(a + b)
        case (.insert(let a), .insert(let b)): result[result.count - 1] = .insert(a + b)
        default: result.append(op)
        }
    }
}
