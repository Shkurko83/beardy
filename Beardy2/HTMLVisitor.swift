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
    
    mutating func defaultVisit(_ markup: Markup) -> String {
        var result = ""
        for child in markup.children {
            result += visit(child)
        }
        return result
    }
    
    // Обработка мягких и жестких переносов строк
    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        return "<br>" // Это не даст тексту слипаться в одну строку
    }
    
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        return "<br>"
    }
    
    mutating func visitText(_ text: Text) -> String {
        return text.string
    }
    
    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        return "<p>\(defaultVisit(paragraph))</p>"
    }
    
    mutating func visitStrong(_ strong: Strong) -> String {
        // Это обработает **текст**
        return "<strong>\(defaultVisit(strong))</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        // Это обработает *текст*
        return "<em>\(defaultVisit(emphasis))</em>"
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
}
