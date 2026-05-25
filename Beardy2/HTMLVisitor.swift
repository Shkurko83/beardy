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
    
    let documentURL: URL?
    
    init(documentURL: URL? = nil) {
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
    
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        return "<hr>\n"
    }
    
    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        return "<blockquote>\(defaultVisit(blockQuote))</blockquote>\n"
    }
    
    mutating func visitUnorderedList(_ list: UnorderedList) -> String {
        return "<ul>\(defaultVisit(list))</ul>\n"
    }
    
    mutating func visitOrderedList(_ list: OrderedList) -> String {
        return "<ol>\(defaultVisit(list))</ol>\n"
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
    
    // ТАБЛИЦЫ
    mutating func visitTable(_ table: Table) -> String {
        return "<table style='border-collapse:collapse; width:100%; margin:15px 0;'>\(visit(table.head))\(visit(table.body))</table>"
    }
    
    mutating func visitTableHead(_ head: Table.Head) -> String {
        return "<thead style='background:rgba(128,128,128,0.2);'>\(defaultVisit(head))</thead>"
    }
    
    mutating func visitTableRow(_ row: Table.Row) -> String {
        return "<tr>\(defaultVisit(row))</tr>"
    }
    
    mutating func visitTableCell(_ cell: Table.Cell) -> String {
        return "<td style='border:1px solid #666; padding:8px;'>\(defaultVisit(cell) == "" ? "&nbsp;" : defaultVisit(cell))</td>"
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
