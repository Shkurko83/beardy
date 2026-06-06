import Foundation
import Markdown

/// List diff aligned per list item, preserving nested sub-lists.
enum ListDiffRenderer {

    private struct ParsedList {
        let isOrdered: Bool
        let isTaskList: Bool
        let items: [ParsedListItem]
    }

    private struct ParsedListItem {
        let plainText: String
        let bodyMarkdown: String
        let checkbox: Checkbox?
        let nestedList: ParsedList?
    }

    private enum ListItemAlignment {
        case equal(old: ParsedListItem, new: ParsedListItem)
        case changed(old: ParsedListItem, new: ParsedListItem)
        case deleted(ParsedListItem)
        case inserted(ParsedListItem)
    }

    static func renderListWordDiff(
        oldMarkdown: String,
        newMarkdown: String,
        documentURL: URL?
    ) -> String {
        guard let oldList = parseListBlock(oldMarkdown),
              let newList = parseListBlock(newMarkdown),
              oldList.isOrdered == newList.isOrdered else {
            return DiffMarkupRenderer.renderBlock(newMarkdown, documentURL: documentURL)
        }
        return renderParsedListDiff(old: oldList, new: newList, documentURL: documentURL)
    }

    /// Line-based list HTML (preserves nested ordered/unordered items). Returns nil if `markdown` is not a list.
    static func renderListPreservingNesting(_ markdown: String, documentURL: URL?) -> String? {
        guard let list = parseListBlock(markdown) else { return nil }
        return renderParsedListDiff(old: list, new: list, documentURL: documentURL)
    }

    // MARK: - Render

    private static func renderParsedListDiff(
        old: ParsedList,
        new: ParsedList,
        documentURL: URL?
    ) -> String {
        let tag = new.isOrdered ? "ol" : "ul"
        let listClasses = listClassNames(isOrdered: new.isOrdered, isTaskList: new.isTaskList)
        var html = "<\(tag) class=\"\(listClasses)\">"
        for alignment in alignListItems(old: old.items, new: new.items) {
            switch alignment {
            case .equal(let oldItem, let newItem):
                html += renderEqualListItemHTML(old: oldItem, new: newItem, documentURL: documentURL)
            case .changed(let oldItem, let newItem):
                html += renderChangedListItemHTML(old: oldItem, new: newItem, documentURL: documentURL)
            case .deleted(let item):
                html += renderDeletedListItemHTML(item)
            case .inserted(let item):
                html += renderInsertedListItemHTML(item, documentURL: documentURL)
            }
        }
        html += "</\(tag)>\n"
        return html
    }

    private static func renderEqualListItemHTML(
        old: ParsedListItem,
        new: ParsedListItem,
        documentURL: URL?
    ) -> String {
        let body: String
        if old.plainText == new.plainText, old.bodyMarkdown == new.bodyMarkdown, old.checkbox == new.checkbox {
            body = renderListItemBody(new, documentURL: documentURL)
        } else {
            body = renderListItemBodyDiff(old: old, new: new, documentURL: documentURL)
        }
        let nested = renderNestedListDiff(old: old.nestedList, new: new.nestedList, documentURL: documentURL)
        let checkboxDiff: (Checkbox?, Checkbox?)? = old.checkbox == new.checkbox ? nil : (old.checkbox, new.checkbox)
        return renderListItem(new, body: body + nested, checkboxDiff: checkboxDiff)
    }

    private static func renderChangedListItemHTML(
        old: ParsedListItem,
        new: ParsedListItem,
        documentURL: URL?
    ) -> String {
        let body = renderListItemBodyDiff(old: old, new: new, documentURL: documentURL)
        let nested = renderNestedListDiff(old: old.nestedList, new: new.nestedList, documentURL: documentURL)
        return renderListItem(new, body: body + nested, checkboxDiff: (old.checkbox, new.checkbox))
    }

    private static func renderDeletedListItemHTML(_ item: ParsedListItem) -> String {
        let liClass = item.checkbox != nil ? "diff-list-item-del task-list-item" : "diff-list-item-del"
        let nested = renderNestedListAsDeleted(item.nestedList)
        return "<li class=\"\(liClass)\">\(checkboxHTML(item.checkbox))<span class=\"diff-del\">\(DiffMarkupRenderer.escapeHTML(item.plainText))</span>\(nested)</li>\n"
    }

    private static func renderInsertedListItemHTML(_ item: ParsedListItem, documentURL: URL?) -> String {
        let body = renderListItemBody(item, documentURL: documentURL)
        let label = body.isEmpty ? DiffMarkupRenderer.escapeHTML(item.plainText) : body
        let nested = renderNestedListHTML(item.nestedList, documentURL: documentURL)
        let liClass = item.checkbox != nil ? "diff-list-item-ins task-list-item" : "diff-list-item-ins"
        return "<li class=\"\(liClass)\">\(checkboxHTML(item.checkbox))<span class=\"diff-ins\">\(label)</span>\(nested)</li>\n"
    }

    private static func renderNestedListHTML(_ list: ParsedList?, documentURL: URL?) -> String {
        guard let list else { return "" }
        return renderParsedListDiff(old: list, new: list, documentURL: documentURL)
    }

    private static func renderNestedListDiff(
        old: ParsedList?,
        new: ParsedList?,
        documentURL: URL?
    ) -> String {
        switch (old, new) {
        case (nil, nil):
            return ""
        case (nil, let new?):
            return wrapNestedListAsInserted(new, documentURL: documentURL)
        case (let old?, nil):
            return wrapNestedListAsDeleted(old)
        case (let old?, let new?):
            if old.isOrdered == new.isOrdered {
                return renderParsedListDiff(old: old, new: new, documentURL: documentURL)
            }
            return wrapNestedListAsDeleted(old) + wrapNestedListAsInserted(new, documentURL: documentURL)
        }
    }

    private static func renderNestedListAsDeleted(_ list: ParsedList?) -> String {
        guard let list else { return "" }
        return wrapNestedListAsDeleted(list)
    }

    private static func wrapNestedListAsDeleted(_ list: ParsedList) -> String {
        let tag = list.isOrdered ? "ol" : "ul"
        var html = "<\(tag) class=\"diff-list diff-nested-list\">"
        for item in list.items {
            html += renderDeletedListItemHTML(item)
        }
        html += "</\(tag)>\n"
        return html
    }

    private static func wrapNestedListAsInserted(_ list: ParsedList, documentURL: URL?) -> String {
        let tag = list.isOrdered ? "ol" : "ul"
        var html = "<\(tag) class=\"diff-list diff-nested-list\">"
        for item in list.items {
            html += renderInsertedListItemHTML(item, documentURL: documentURL)
        }
        html += "</\(tag)>\n"
        return html
    }

    // MARK: - Parse

    private static func parseListBlock(_ source: String) -> ParsedList? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Prefer indentation tree from raw source — Swift Markdown often flattens 2-space nested lists.
        if let fromLines = parseListLines(trimmed) {
            return fromLines
        }

        let processed = trimmed
            .components(separatedBy: "\n")
            .map { $0.isEmpty ? "\u{00A0}" : $0 }
            .joined(separator: "\n")

        let document = Document(parsing: processed)
        for child in document.children {
            if let list = child as? UnorderedList {
                return parseList(from: list, isOrdered: false)
            }
            if let list = child as? OrderedList {
                return parseList(from: list, isOrdered: true)
            }
        }
        return nil
    }

    private static func parseList(from list: Markup, isOrdered: Bool) -> ParsedList {
        let items = list.children.compactMap { child -> ParsedListItem? in
            guard let item = child as? ListItem else { return nil }
            return parseListItem(item)
        }
        return ParsedList(
            isOrdered: isOrdered,
            isTaskList: items.contains { $0.checkbox != nil },
            items: items
        )
    }

    private static func parseListItem(_ item: ListItem) -> ParsedListItem {
        let plain = listItemLabelPlainText(item)
        let body = listItemBodyMarkdown(item)
        let nested = nestedList(from: item)
        return ParsedListItem(
            plainText: plain,
            bodyMarkdown: body,
            checkbox: item.checkbox,
            nestedList: nested
        )
    }

    private static func nestedList(from item: ListItem) -> ParsedList? {
        for child in item.children {
            if let list = child as? UnorderedList {
                return parseList(from: list, isOrdered: false)
            }
            if let list = child as? OrderedList {
                return parseList(from: list, isOrdered: true)
            }
        }
        return nil
    }

    private static func listItemLabelPlainText(_ item: ListItem) -> String {
        var parts: [String] = []
        for child in item.children {
            if child is UnorderedList || child is OrderedList { continue }
            collectPlainText(from: child, into: &parts)
        }
        return parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func listItemBodyMarkdown(_ item: ListItem) -> String {
        var parts: [String] = []
        for child in item.children {
            if child is UnorderedList || child is OrderedList { continue }
            let formatted = child.format().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !formatted.isEmpty else { continue }
            parts.append(stripListMarker(formatted))
        }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseListLines(_ source: String) -> ParsedList? {
        let rawLines = source.components(separatedBy: "\n")
        guard !rawLines.isEmpty else { return nil }

        struct LineEntry {
            let indent: Int
            let line: String
        }

        var entries: [LineEntry] = []
        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, isListMarkerLine(trimmed) else { continue }
            let indent = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
            entries.append(LineEntry(indent: indent, line: trimmed))
        }
        guard let first = entries.first else { return nil }

        let isOrdered = first.line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil

        func buildItems(from start: Int, levelIndent: Int) -> ([ParsedListItem], Int) {
            var items: [ParsedListItem] = []
            var index = start
            while index < entries.count {
                let entry = entries[index]
                if entry.indent < levelIndent { break }
                if entry.indent > levelIndent {
                    index += 1
                    continue
                }

                let parsed = parseListLine(entry.line)
                index += 1
                var nested: ParsedList?
                if index < entries.count, entries[index].indent > levelIndent {
                    let childIndent = entries[index].indent
                    let nestedOrdered = entries[index].line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
                    let (nestedItems, nextIndex) = buildItems(from: index, levelIndent: childIndent)
                    index = nextIndex
                    if !nestedItems.isEmpty {
                        nested = ParsedList(
                            isOrdered: nestedOrdered,
                            isTaskList: nestedItems.contains { $0.checkbox != nil },
                            items: nestedItems
                        )
                    }
                }
                items.append(
                    ParsedListItem(
                        plainText: parsed.plainText,
                        bodyMarkdown: parsed.bodyMarkdown,
                        checkbox: parsed.checkbox,
                        nestedList: nested
                    )
                )
            }
            return (items, index)
        }

        let (items, _) = buildItems(from: 0, levelIndent: first.indent)
        return ParsedList(
            isOrdered: isOrdered,
            isTaskList: items.contains { $0.checkbox != nil },
            items: items
        )
    }

    private static func parseListLine(_ line: String) -> ParsedListItem {
        var t = line.trimmingCharacters(in: .whitespaces)
        let bulletPatterns = [#"^[-*+]\s+"#, #"^\d+\.\s+"#]
        for pattern in bulletPatterns {
            if let range = t.range(of: pattern, options: .regularExpression) {
                t = String(t[range.upperBound...])
                break
            }
        }
        let (checkbox, body) = parseTaskMarker(t)
        return ParsedListItem(plainText: body, bodyMarkdown: body, checkbox: checkbox, nestedList: nil)
    }

    private static func stripListMarker(_ line: String) -> String {
        let patterns = [
            #"^[-*+]\s*\[[xX ]\]\s+"#,
            #"^[-*+]\s*\[[xX]\]\s+"#,
            #"^[-*+]\s+"#,
            #"^\d+\.\s+"#
        ]
        for pattern in patterns {
            if let range = line.range(of: pattern, options: .regularExpression) {
                return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return line
    }

    // MARK: - Align items

    private static func alignListItems(
        old: [ParsedListItem],
        new: [ParsedListItem]
    ) -> [ListItemAlignment] {
        let ops = BlockDiffLCS.diff(
            old: old.map(alignmentKey),
            new: new.map(alignmentKey)
        )

        var result: [ListItemAlignment] = []
        var oldIndex = 0
        var newIndex = 0
        var opIndex = 0

        while opIndex < ops.count {
            switch ops[opIndex] {
            case .equal(let count):
                for _ in 0..<count {
                    guard oldIndex < old.count, newIndex < new.count else { break }
                    result.append(.equal(old: old[oldIndex], new: new[newIndex]))
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

    // MARK: - Task list helpers

    private static func listClassNames(isOrdered: Bool, isTaskList: Bool) -> String {
        var names = ["diff-list"]
        if isTaskList { names.append("task-list") }
        return names.joined(separator: " ")
    }

    private static func alignmentKey(_ item: ParsedListItem) -> String {
        var key = item.plainText
        if let checkbox = item.checkbox {
            let marker = checkbox == .checked ? "[x]" : "[ ]"
            key = "\(marker) \(key)"
        }
        return key
    }

    private static func isListMarkerLine(_ line: String) -> Bool {
        line.hasPrefix("- ")
            || line.hasPrefix("* ")
            || line.hasPrefix("+ ")
            || line.hasPrefix("- [")
            || line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
    }

    private static func parseTaskMarker(_ body: String) -> (Checkbox?, String) {
        let patterns: [(String, Checkbox)] = [
            (#"^\[[xX]\]\s+"#, .checked),
            (#"^\[[ ]\]\s+"#, .unchecked)
        ]
        for (pattern, state) in patterns {
            if let range = body.range(of: pattern, options: .regularExpression) {
                let stripped = String(body[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return (state, stripped)
            }
        }
        return (nil, body)
    }

    private static func checkboxHTML(_ checkbox: Checkbox?) -> String {
        guard let checkbox else { return "" }
        let checked = checkbox == .checked ? "checked " : ""
        return "<input type=\"checkbox\" class=\"diff-task-checkbox\" \(checked)disabled> "
    }

    private static func renderCheckboxDiff(old: Checkbox?, new: Checkbox?) -> String {
        if old == new { return checkboxHTML(new) }
        var html = ""
        if let old {
            let wasChecked = old == .checked ? "checked " : ""
            html += "<span class=\"diff-del\"><input type=\"checkbox\" class=\"diff-task-checkbox\" \(wasChecked)disabled></span> "
        }
        if let new {
            html += "<span class=\"diff-ins\">\(checkboxHTML(new).trimmingCharacters(in: .whitespaces))</span> "
        }
        return html
    }

    private static func renderListItem(
        _ item: ParsedListItem,
        body: String,
        checkboxDiff: (Checkbox?, Checkbox?)? = nil
    ) -> String {
        let liClass = item.checkbox != nil ? "task-list-item" : ""
        let classAttr = liClass.isEmpty ? "" : " class=\"\(liClass)\""
        let checkboxPart: String
        if let (old, new) = checkboxDiff {
            checkboxPart = renderCheckboxDiff(old: old, new: new)
        } else {
            checkboxPart = checkboxHTML(item.checkbox)
        }
        return "<li\(classAttr)>\(checkboxPart)\(body)</li>\n"
    }

    // MARK: - Render item bodies

    private static func renderListItemBody(_ item: ParsedListItem, documentURL: URL?) -> String {
        renderInlineMarkdownBody(item.bodyMarkdown, documentURL: documentURL)
    }

    private static func renderListItemBodyDiff(
        old: ParsedListItem,
        new: ParsedListItem,
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

    private static func renderInlineMarkdownBody(_ markdown: String, documentURL: URL?) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
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

    private static func collectPlainText(from markup: Markup, into parts: inout [String]) {
        for child in markup.children {
            if child is UnorderedList || child is OrderedList { continue }
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
}
