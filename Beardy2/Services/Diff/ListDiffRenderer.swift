import Foundation
import Markdown

/// List diff aligned per list item (not flat word stream across the whole list).
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
    }

    private enum ListItemAlignment {
        case equal(ParsedListItem)
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

        let tag = newList.isOrdered ? "ol" : "ul"
        let listClasses = listClassNames(isOrdered: newList.isOrdered, isTaskList: newList.isTaskList)
        var html = "<\(tag) class=\"\(listClasses)\">"
        for alignment in alignListItems(old: oldList.items, new: newList.items) {
            switch alignment {
            case .equal(let item):
                html += renderListItem(item, body: renderListItemBody(item, documentURL: documentURL))
            case .changed(let oldItem, let newItem):
                let body = renderListItemBodyDiff(old: oldItem, new: newItem, documentURL: documentURL)
                html += renderListItem(newItem, body: body, checkboxDiff: (oldItem.checkbox, newItem.checkbox))
            case .deleted(let item):
                let liClass = item.checkbox != nil ? "diff-list-item-del task-list-item" : "diff-list-item-del"
                html += "<li class=\"\(liClass)\">\(checkboxHTML(item.checkbox))<span class=\"diff-del\">\(DiffMarkupRenderer.escapeHTML(item.plainText))</span></li>\n"
            case .inserted(let item):
                let liClass = item.checkbox != nil ? "diff-list-item-ins task-list-item" : "diff-list-item-ins"
                html += "<li class=\"\(liClass)\">\(checkboxHTML(item.checkbox))<span class=\"diff-ins\">\(DiffMarkupRenderer.escapeHTML(item.plainText))</span></li>\n"
            }
        }
        html += "</\(tag)>\n"
        return html
    }

    // MARK: - Parse

    private static func parseListBlock(_ source: String) -> ParsedList? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let processed = trimmed
            .components(separatedBy: "\n")
            .map { $0.isEmpty ? "\u{00A0}" : $0 }
            .joined(separator: "\n")

        let document = Document(parsing: processed)
        for child in document.children {
            if let list = child as? UnorderedList {
                let parsed = items(from: list)
                return ParsedList(
                    isOrdered: false,
                    isTaskList: parsed.contains { $0.checkbox != nil },
                    items: parsed
                )
            }
            if let list = child as? OrderedList {
                let parsed = items(from: list)
                return ParsedList(
                    isOrdered: true,
                    isTaskList: parsed.contains { $0.checkbox != nil },
                    items: parsed
                )
            }
        }
        return parseListLines(trimmed)
    }

    private static func items(from list: Markup) -> [ParsedListItem] {
        list.children.compactMap { child -> ParsedListItem? in
            guard let item = child as? ListItem else { return nil }
            let plain = listItemPlainText(item)
            let body = listItemBodyMarkdown(item)
            return ParsedListItem(plainText: plain, bodyMarkdown: body, checkbox: item.checkbox)
        }
    }

    private static func listItemPlainText(_ item: ListItem) -> String {
        if let container = item as? InlineContainer {
            return container.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var parts: [String] = []
        collectPlainText(from: item, into: &parts)
        return parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func listItemBodyMarkdown(_ item: ListItem) -> String {
        let formatted = item.format().trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^[-*+]\s+"#,
            #"^\d+\.\s+"#,
            #"^[-*+]\s*\[[xX ]\]\s+"#,
            #"^[-*+]\s*\[[xX]\]\s+"#
        ]
        var body = formatted
        for pattern in patterns {
            if let range = body.range(of: pattern, options: .regularExpression) {
                body = String(body[range.upperBound...])
                break
            }
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseListLines(_ source: String) -> ParsedList? {
        let lines = source.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return nil }
        let first = lines[0].trimmingCharacters(in: .whitespaces)
        let isOrdered = first.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
        var items: [ParsedListItem] = []
        for line in lines {
            items.append(parseListLine(line))
        }
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
        return ParsedListItem(plainText: body, bodyMarkdown: body, checkbox: checkbox)
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

    // MARK: - Task list helpers

    private static func listClassNames(isOrdered: Bool, isTaskList: Bool) -> String {
        var names = ["diff-list"]
        if isTaskList { names.append("task-list") }
        return names.joined(separator: " ")
    }

    private static func alignmentKey(_ item: ParsedListItem) -> String {
        guard let checkbox = item.checkbox else { return item.plainText }
        let marker = checkbox == .checked ? "[x]" : "[ ]"
        return "\(marker) \(item.plainText)"
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

    private static func collectPlainText(from markup: Markup, into parts: inout [String]) {
        for child in markup.children {
            if let text = child as? Text {
                parts.append(text.string)
            } else if child is SoftBreak || child is LineBreak {
                parts.append(" ")
            } else {
                collectPlainText(from: child, into: &parts)
            }
        }
    }
}
