//
//  HTMLVisitor.swift
//  Beardy2
//
//  Created by Butt Simpson on 30.12.2025.
//

import Markdown
import Foundation

struct HTMLVisitor: MarkupVisitor {
    typealias Result = String
    
    let sourceMarkdown: String?
    let documentURL: URL?
    
    init(sourceMarkdown: String? = nil, documentURL: URL? = nil) {
        self.sourceMarkdown = sourceMarkdown
        self.documentURL = documentURL
    }
    
    mutating func defaultVisit(_ markup: Markup) -> String {
        var result = ""
        for child in markup.children {
            result += visit(child)
        }
        return result
    }
    
    // Обработка мягких и жестких переносов строк
    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        return "<br>\n"
    }
    
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        return "<br>\n"
    }
    
    mutating func visitText(_ text: Text) -> String {
        return text.string
    }
    
    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let content = defaultVisit(paragraph)
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content == "\u{00A0}" {
            return "<p>&nbsp;</p>\n"
        }
        return "<p>\(content)</p>\n"
    }
    
    mutating func visitStrong(_ strong: Strong) -> String {
        // Это обработает **текст**
        return "<strong>\(defaultVisit(strong))</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        // Это обработает *текст*
        return "<em>\(defaultVisit(emphasis))</em>"
    }
    
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        return "<del>\(defaultVisit(strikethrough))</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escapeInlineText(inlineCode.code))</code>"
    }
    
    mutating func visitLink(_ link: Markdown.Link) -> String {
        let href = htmlAttribute(link.destination ?? "")
        var attrs = ["href=\"\(href)\"", "target=\"_blank\"", "rel=\"noopener noreferrer\""]
        if let title = link.title, !title.isEmpty {
            attrs.append("title=\"\(htmlAttribute(title))\"")
        }
        return "<a \(attrs.joined(separator: " "))>\(defaultVisit(link))</a>"
    }

    private func htmlAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }

    private func escapeInlineText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        return "<hr>\n"
    }
    
    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        return "<blockquote>\(defaultVisit(blockQuote))</blockquote>\n"
    }
    
    mutating func visitUnorderedList(_ list: UnorderedList) -> String {
        let isTaskList = list.children.contains { ($0 as? ListItem)?.checkbox != nil }
        let classAttr = isTaskList ? " class=\"task-list\"" : ""
        return "<ul\(classAttr)>\(defaultVisit(list))</ul>\n"
    }
    
    mutating func visitOrderedList(_ list: OrderedList) -> String {
        if let html = renderedListHTML(from: list, ordered: true) {
            return html
        }
        return "<ol>\(defaultVisit(list))</ol>\n"
    }

    private mutating func renderedListHTML(from list: Markup, ordered: Bool) -> String? {
        guard let sourceMarkdown, let range = list.range else { return nil }
        let lines = sourceMarkdown.components(separatedBy: "\n")
        let startLine = max(0, range.lowerBound.line - 1)
        let endLine = min(lines.count - 1, max(startLine, range.upperBound.line - 1))
        guard startLine < lines.count else { return nil }
        let rough = lines[startLine...endLine].joined(separator: "\n")
        guard let block = DocxMarkdownListParser.extractListBlock(from: rough, ordered: ordered),
              let parsed = DocxMarkdownListParser.parse(source: block) else {
            return nil
        }
        return renderParsedListHTML(parsed)
    }

    private mutating func renderParsedListHTML(_ list: DocxParsedList) -> String {
        let tag = list.isOrdered ? "ol" : "ul"
        let classAttr = list.isTaskList ? " class=\"task-list\"" : ""
        var html = "<\(tag)\(classAttr)>\n"
        for item in list.items {
            if item.checkbox != nil {
                html += "<li class=\"task-list-item\">"
                let checked = item.checkbox == true ? "checked " : ""
                html += "<input type=\"checkbox\" \(checked)disabled> "
            } else {
                html += "<li>"
            }
            html += renderListItemBodyHTML(item.bodyMarkdown)
            if let nested = item.nestedList {
                html += renderParsedListHTML(nested)
            }
            html += "</li>\n"
        }
        html += "</\(tag)>\n"
        return html
    }

    private mutating func renderListItemBodyHTML(_ markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let doc = Document(parsing: trimmed)
        var html = visit(doc)
        if html.hasPrefix("<p>"), html.hasSuffix("</p>\n") {
            html = String(html.dropFirst(3).dropLast(5))
        } else if html.hasSuffix("</p>\n") {
            html = String(html.dropLast(5))
        }
        return html
    }
    
    mutating func visitListItem(_ listItem: ListItem) -> String {
        var inner = ""
        for child in listItem.children {
            if let paragraph = child as? Paragraph {
                let html = defaultVisit(paragraph)
                inner += html
                    .replacingOccurrences(of: "<p>", with: "")
                    .replacingOccurrences(of: "</p>\n", with: "<br>\n")
                    .replacingOccurrences(of: "</p>", with: "")
            } else {
                inner += visit(child)
            }
        }
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? "checked " : ""
            return "<li class=\"task-list-item\"><input type=\"checkbox\" \(checked)disabled> \(inner)</li>\n"
        }
        return "<li>\(inner)</li>\n"
    }
    
    // Блоки кода с сохранением форматирования (white-space: pre)
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let escapedCode = codeBlock.code
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        
        // Берем язык из Markdown (например, ```swift) или ставим plaintext
        let lang = codeBlock.language ?? "plaintext"
        
        // Highlight.js ищет класс в формате "language-swift"
        return "<pre><code class=\"language-\(lang)\">\(escapedCode)</code></pre>"
    }
    
    // ТАБЛИЦЫ — GFM line parser (как Live), без лишних пустых строк Swift Markdown
    mutating func visitTable(_ table: Table) -> String {
        let source = table.format()
        if let model = TableModel.parse(source: source), !model.cells.isEmpty {
            return renderGFMTable(model: model, alignments: table.columnAlignments)
        }
        return "<table style='border-collapse:collapse; width:100%; margin:15px 0;'>\(visit(table.head))\(visit(table.body))</table>"
    }

    private func renderGFMTable(model: TableModel, alignments: [Table.ColumnAlignment?]) -> String {
        let cellStyle = "border:1px solid #666; padding:8px;"
        var html = "<table style='border-collapse:collapse; width:100%; margin:15px 0;'>"
        html += "<thead style='background:rgba(128,128,128,0.2);'><tr>"
        for (colIndex, cell) in model.cells[0].enumerated() {
            html += "<th style=\"\(cellStyle)\(columnAlignCSS(alignments, colIndex))\">\(renderTableCellMarkup(cell))</th>"
        }
        html += "</tr></thead><tbody>"
        for row in model.cells.dropFirst() {
            guard row.contains(where: { !isBlankTableCell($0) }) else { continue }
            html += "<tr>"
            for (colIndex, cell) in row.enumerated() {
                let inner = renderTableCellMarkup(cell)
                html += "<td style=\"\(cellStyle)\(columnAlignCSS(alignments, colIndex))\">\(inner.isEmpty ? "&nbsp;" : inner)</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>\n"
        return html
    }

    private func renderTableCellMarkup(_ markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBlankTableCell(trimmed) else { return "" }
        let doc = Document(parsing: trimmed)
        var visitor = HTMLVisitor(documentURL: documentURL)
        var html = visitor.visit(doc)
        if html.hasPrefix("<p>"), html.hasSuffix("</p>\n") {
            html = String(html.dropFirst(3).dropLast(5))
        } else if html.hasSuffix("</p>\n") {
            html = String(html.dropLast(5))
        }
        return html
    }

    private func columnAlignCSS(_ alignments: [Table.ColumnAlignment?], _ colIndex: Int) -> String {
        guard colIndex < alignments.count, let alignment = alignments[colIndex] else { return "" }
        let value: String
        switch alignment {
        case .left: value = "left"
        case .center: value = "center"
        case .right: value = "right"
        }
        return " text-align:\(value);"
    }

    private func isBlankTableCell(_ text: String) -> Bool {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
    
    mutating func visitTableHead(_ head: Table.Head) -> String {
        return "<thead style='background:rgba(128,128,128,0.2);'>\(defaultVisit(head))</thead>"
    }
    
    mutating func visitTableRow(_ row: Table.Row) -> String {
        return "<tr>\(defaultVisit(row))</tr>"
    }
    
    mutating func visitTableCell(_ cell: Table.Cell) -> String {
        let inner = defaultVisit(cell)
        return "<td style='border:1px solid #666; padding:8px;'>\(inner.isEmpty ? "&nbsp;" : inner)</td>"
    }
    
    mutating func visitHeading(_ heading: Heading) -> String {
        let level = heading.level
        let content = defaultVisit(heading)
        let id = headingSlug(heading.plainText)
        return "<h\(level) id=\"\(htmlAttribute(id))\">\(content)</h\(level)>\n"
    }

    private func headingSlug(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
    
    mutating func visitImage(_ image: Markdown.Image) -> String {
        let rawSrc = image.source ?? ""
        let alt = image.plainText
        let finalSrc = resolveImageSource(rawSrc)
        return "<img src=\"\(finalSrc)\" alt=\"\(alt)\" style=\"max-width:100%; height:auto;\">"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        rewriteImageSources(in: html.rawHTML)
    }

    mutating func visitInlineHTML(_ html: InlineHTML) -> String {
        rewriteImageSources(in: html.rawHTML)
    }

    private func resolveImageSource(_ rawSrc: String) -> String {
        if rawSrc.hasPrefix("data:")
            || rawSrc.hasPrefix("http://")
            || rawSrc.hasPrefix("https://")
            || rawSrc.hasPrefix("beardy://") {
            return rawSrc
        }

        if rawSrc.hasPrefix("file://") {
            let filePath = rawSrc.replacingOccurrences(of: "file://", with: "")
            return ImageInsertionHelper.beardyURL(forLocalPath: filePath)
        }

        if rawSrc.hasPrefix("/") {
            return ImageInsertionHelper.beardyURL(forLocalPath: rawSrc)
        }

        if let docURL = documentURL {
            let docDir = docURL.deletingLastPathComponent()
            let relativePath = rawSrc.hasPrefix("./") ? String(rawSrc.dropFirst(2)) : rawSrc
            let absolutePath = docDir.appendingPathComponent(relativePath).path
            return ImageInsertionHelper.beardyURL(forLocalPath: absolutePath)
        }

        return rawSrc
    }

    private func rewriteImageSources(in html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"src=(["'])([^"']+)\1"#,
            options: .caseInsensitive
        ) else {
            return html
        }

        let nsHTML = html as NSString
        var result = html
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).reversed()

        for match in matches {
            let quote = nsHTML.substring(with: match.range(at: 1))
            let src = nsHTML.substring(with: match.range(at: 2))
            let resolved = resolveImageSource(src)
            let replacement = "src=\(quote)\(resolved)\(quote)"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        return result
    }

}
