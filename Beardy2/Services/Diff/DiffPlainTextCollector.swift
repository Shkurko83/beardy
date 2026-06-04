import Foundation
import Markdown

/// Plain text for word diff — same spacing rules as `RichWordDiffHTMLWalker`.
enum DiffPlainTextCollector {

    static func plainText(fromMarkdown source: String) -> String {
        guard let document = parseDocument(source) else { return "" }
        var builder = Builder()
        builder.collect(document)
        return builder.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseDocument(_ source: String) -> Document? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let processed = trimmed
            .components(separatedBy: "\n")
            .map { $0.isEmpty ? "\u{00A0}" : $0 }
            .joined(separator: "\n")
        return Document(parsing: processed)
    }

    private struct Builder: MarkupVisitor {
        typealias Result = Void

        var text = ""

        mutating func collect(_ markup: Markup) {
            _ = visit(markup)
        }

        mutating func defaultVisit(_ markup: Markup) -> Void {
            for child in markup.children {
                visit(child)
            }
        }

        mutating func joinInlineChildren(_ markup: Markup) {
            for child in markup.children {
                visit(child)
            }
        }

        mutating func appendFragment(_ fragment: String) {
            guard !fragment.isEmpty else { return }
            if !text.isEmpty, needsSpaceBetween(text, fragment) {
                text += " "
            }
            text += fragment
        }

        private func needsSpaceBetween(_ left: String, _ right: String) -> Bool {
            guard let last = left.last, let first = right.first else { return false }
            return !last.isWhitespace && !first.isWhitespace
        }

        mutating func visitHeading(_ heading: Heading) -> Void {
            joinInlineChildren(heading)
        }

        mutating func visitParagraph(_ paragraph: Paragraph) -> Void {
            joinInlineChildren(paragraph)
        }

        mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> Void {
            defaultVisit(blockQuote)
        }

        mutating func visitUnorderedList(_ list: UnorderedList) -> Void {
            defaultVisit(list)
        }

        mutating func visitOrderedList(_ list: OrderedList) -> Void {
            defaultVisit(list)
        }

        mutating func visitListItem(_ listItem: ListItem) -> Void {
            joinInlineChildren(listItem)
        }

        mutating func visitStrong(_ strong: Strong) -> Void {
            joinInlineChildren(strong)
        }

        mutating func visitEmphasis(_ emphasis: Emphasis) -> Void {
            joinInlineChildren(emphasis)
        }

        mutating func visitLink(_ link: Link) -> Void {
            joinInlineChildren(link)
        }

        mutating func visitInlineCode(_ inlineCode: InlineCode) -> Void {
            appendFragment(inlineCode.code)
        }

        mutating func visitText(_ text: Text) -> Void {
            appendFragment(text.string)
        }

        mutating func visitSoftBreak(_ softBreak: SoftBreak) -> Void {
            if !text.isEmpty, text.last?.isWhitespace != true {
                text += " "
            }
        }

        mutating func visitLineBreak(_ lineBreak: LineBreak) -> Void {
            if !text.isEmpty, text.last?.isWhitespace != true {
                text += " "
            }
        }

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Void {
            appendFragment(codeBlock.code)
        }
    }
}
