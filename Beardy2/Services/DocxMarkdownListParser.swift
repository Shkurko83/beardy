//
//  DocxMarkdownListParser.swift
//  Beardy2
//
//  Line-based GFM list tree (preserves 2-space nesting; Swift Markdown often flattens lists).
//

import Foundation

struct DocxParsedList {
    let isOrdered: Bool
    let isTaskList: Bool
    let items: [DocxParsedListItem]
}

struct DocxParsedListItem {
    let bodyMarkdown: String
    let checkbox: Bool?
    let nestedList: DocxParsedList?
}

enum DocxMarkdownListParser {
    /// Extracts a contiguous list block of the requested type from a rough source range.
    static func extractListBlock(from source: String, ordered: Bool) -> String? {
        let rawLines = source.components(separatedBy: "\n")
        var startIndex: Int?
        for (index, raw) in rawLines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if ordered, isOrderedMarker(trimmed) {
                startIndex = index
                break
            }
            if !ordered, isUnorderedMarker(trimmed) {
                startIndex = index
                break
            }
        }
        guard let start = startIndex else { return nil }

        var collected: [String] = []
        for index in start..<rawLines.count {
            let raw = rawLines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            guard isListMarkerLine(trimmed) else { break }
            if ordered {
                guard isOrderedMarker(trimmed) else { break }
            } else {
                guard isUnorderedMarker(trimmed) else { break }
            }
            collected.append(raw)
        }
        guard !collected.isEmpty else { return nil }
        return collected.joined(separator: "\n")
    }

    static func isOrderedMarker(_ line: String) -> Bool {
        line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
    }

    static func isUnorderedMarker(_ line: String) -> Bool {
        isListMarkerLine(line) && !isOrderedMarker(line)
    }

    static func parse(source: String) -> DocxParsedList? {
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

        func buildItems(from start: Int, levelIndent: Int) -> ([DocxParsedListItem], Int) {
            var items: [DocxParsedListItem] = []
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
                var nested: DocxParsedList?
                if index < entries.count, entries[index].indent > levelIndent {
                    let childIndent = entries[index].indent
                    let nestedOrdered = entries[index].line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
                    let (nestedItems, nextIndex) = buildItems(from: index, levelIndent: childIndent)
                    index = nextIndex
                    if !nestedItems.isEmpty {
                        nested = DocxParsedList(
                            isOrdered: nestedOrdered,
                            isTaskList: nestedItems.contains { $0.checkbox != nil },
                            items: nestedItems
                        )
                    }
                }
                items.append(
                    DocxParsedListItem(
                        bodyMarkdown: parsed.body,
                        checkbox: parsed.checkbox,
                        nestedList: nested
                    )
                )
            }
            return (items, index)
        }

        let (items, _) = buildItems(from: 0, levelIndent: first.indent)
        guard !items.isEmpty else { return nil }
        return DocxParsedList(
            isOrdered: isOrdered,
            isTaskList: items.contains { $0.checkbox != nil },
            items: items
        )
    }

    private static func isListMarkerLine(_ line: String) -> Bool {
        let patterns = [
            #"^[-*+]\s*\[[xX ]\]\s+"#,
            #"^[-*+]\s*\[[xX]\]\s+"#,
            #"^[-*+]\s+"#,
            #"^\d+\.\s+"#
        ]
        return patterns.contains { line.range(of: $0, options: .regularExpression) != nil }
    }

    private static func parseListLine(_ line: String) -> (body: String, checkbox: Bool?) {
        var text = line
        let patterns = [#"^[-*+]\s+"#, #"^\d+\.\s+"#]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                text = String(text[range.upperBound...])
                break
            }
        }
        if let match = text.range(of: #"^\[[ xX]\]\s+"#, options: .regularExpression) {
            let marker = text[text.index(after: text.startIndex)]
            let checked = marker.lowercased() == "x"
            text = String(text[match.upperBound...])
            return (text.trimmingCharacters(in: .whitespaces), checked)
        }
        return (text.trimmingCharacters(in: .whitespaces), nil)
    }
}
