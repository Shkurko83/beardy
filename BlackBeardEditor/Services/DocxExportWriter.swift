//
//  DocxExportWriter.swift
//  BlackBeardEditor
//
//  Native Markdown → DOCX with tables, lists, images, OMML math, and prerendered diagrams.
//

import AppKit
import Foundation
import Markdown

enum DocxExportWriter {
    static func write(
        markdown: String,
        documentURL: URL?,
        title: String,
        rasterAssets: [DocxRasterAsset] = [],
        to outputURL: URL
    ) throws {
        let document = Document(parsing: markdown)
        var builder = DocxDocumentBuilder(
            sourceMarkdown: markdown,
            documentURL: documentURL,
            title: title,
            rasterAssets: rasterAssets
        )
        builder.visit(document)
        try builder.write(to: outputURL)
    }
}

// MARK: - Builder

private struct DocxDocumentBuilder: MarkupVisitor {
    typealias Result = Void

    let sourceMarkdown: String
    let documentURL: URL?
    let title: String

    var paragraphs: [String] = []
    var relationships: [(id: String, type: String, target: String, external: Bool)] = []
    var mediaFiles: [(name: String, data: Data, contentType: String)] = []
    var nextRelID = 5
    var nextMediaIndex = 1
    var rasterQueue: [DocxRasterAsset]

    private var listDepth = 0

    init(sourceMarkdown: String, documentURL: URL?, title: String, rasterAssets: [DocxRasterAsset]) {
        self.sourceMarkdown = sourceMarkdown
        self.documentURL = documentURL
        self.title = title
        self.rasterQueue = rasterAssets
    }

    mutating func defaultVisit(_ markup: Markup) {
        for child in markup.children {
            visit(child)
        }
    }

    mutating func visit(_ markup: Markup) {
        switch markup {
        case let document as Document:
            defaultVisit(document)
        case let heading as Heading:
            visitHeading(heading)
        case let paragraph as Paragraph:
            visitParagraphBlock(paragraph)
        case let blockQuote as BlockQuote:
            visitBlockQuote(blockQuote)
        case let thematicBreak as ThematicBreak:
            visitThematicBreak(thematicBreak)
        case let unorderedList as UnorderedList:
            visitUnorderedList(unorderedList)
        case let orderedList as OrderedList:
            visitOrderedList(orderedList)
        case let codeBlock as CodeBlock:
            visitCodeBlock(codeBlock)
        case let table as Table:
            visitTable(table)
        case let htmlBlock as HTMLBlock:
            appendParagraph(runs: [.init(text: stripHTML(htmlBlock.rawHTML), style: .body)], style: .body)
        default:
            defaultVisit(markup)
        }
    }

    // MARK: Blocks

    mutating func visitHeading(_ heading: Heading) {
        let style: ParagraphStyle
        switch heading.level {
        case 1: style = .heading1
        case 2: style = .heading2
        case 3: style = .heading3
        case 4: style = .heading4
        case 5: style = .heading5
        default: style = .heading6
        }
        appendParagraph(runs: inlineRuns(from: heading), style: style)
    }

    mutating func visitParagraphBlock(_ paragraph: Paragraph) {
        if isImageOnlyParagraph(paragraph), let image = imageFromParagraph(paragraph) {
            if let fileURL = resolveImageFileURL(image.source) {
                embedFileImage(at: fileURL, alt: image.plainText)
            } else {
                appendParagraph(
                    runs: [.init(text: "[Image: \(image.plainText)]", style: .body.withItalic(true))],
                    style: .body
                )
            }
            return
        }

        let plain = plainText(of: paragraph)
        if let displayLatex = DocxMathOMML.isDisplayMathBlock(plain) {
            if consumeRaster(.mathDisplay) {
                return
            }
            if let omml = DocxMathOMML.omml(for: displayLatex, display: true) {
                paragraphs.append("<w:p><w:pPr><w:jc w:val=\"center\"/><w:spacing w:before=\"120\" w:after=\"120\"/></w:pPr>\(omml)</w:p>")
                return
            }
            appendCenteredParagraph(
                runs: [.init(text: displayLatex, style: .body.withItalic(true))],
                style: .body
            )
            return
        }

        let runs = paragraphRuns(from: paragraph)
        guard !runs.isEmpty else { return }
        appendParagraph(runs: runs, style: .body)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        for child in blockQuote.children {
            if let paragraph = child as? Paragraph {
                appendParagraph(runs: paragraphRuns(from: paragraph), style: .blockquote)
            } else {
                visit(child)
            }
        }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        paragraphs.append("<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"999999\"/></w:pBdr><w:spacing w:before=\"120\" w:after=\"120\"/></w:pPr></w:p>")
    }

    mutating func visitUnorderedList(_ list: UnorderedList) {
        if renderListFromSource(list, ordered: false) { return }
        visitListTree(list, numId: 1)
    }

    mutating func visitOrderedList(_ list: OrderedList) {
        if renderListFromSource(list, ordered: true) { return }
        visitListTree(list, numId: 2)
    }

    @discardableResult
    private mutating func renderListFromSource(_ list: Markup, ordered: Bool) -> Bool {
        guard let source = sourceSlice(for: list, ordered: ordered),
              let parsed = DocxMarkdownListParser.parse(source: source) else {
            return false
        }
        renderParsedList(parsed, depth: 1)
        return true
    }

    private func sourceSlice(for markup: Markup, ordered: Bool) -> String? {
        guard let range = markup.range else { return nil }
        let lines = sourceMarkdown.components(separatedBy: "\n")
        let startLine = max(0, range.lowerBound.line - 1)
        let endLine = min(lines.count - 1, max(startLine, range.upperBound.line - 1))
        guard startLine < lines.count else { return nil }
        let rough = lines[startLine...endLine].joined(separator: "\n")
        return DocxMarkdownListParser.extractListBlock(from: rough, ordered: ordered)
    }

    mutating func visitListTree(_ list: Markup, numId: Int) {
        listDepth += 1
        defer { listDepth -= 1 }
        for case let item as ListItem in list.children {
            visitListItem(item, numId: numId)
        }
    }

    mutating func renderParsedList(_ list: DocxParsedList, depth: Int) {
        let numId = list.isOrdered ? 2 : 1
        for item in list.items {
            var runs: [ParagraphRun] = []
            if let checked = item.checkbox {
                runs.append(.text(.init(text: checked ? "☑ " : "☐ ", style: .body)))
            }
            let bodyDoc = Document(parsing: item.bodyMarkdown)
            for child in bodyDoc.children {
                if let paragraph = child as? Paragraph {
                    runs.append(contentsOf: paragraphRuns(from: paragraph).map { .text($0) })
                }
            }
            if !runs.isEmpty {
                appendListParagraph(runs: runs, depth: depth, numId: numId)
            }
            if let nested = item.nestedList {
                renderParsedList(nested, depth: depth + 1)
            }
        }
    }

    mutating func visitListItem(_ listItem: ListItem, numId: Int) {
        var textRuns: [ParagraphRun] = []
        if let checkbox = listItem.checkbox {
            let mark = checkbox == .checked ? "☑ " : "☐ "
            textRuns.append(.text(.init(text: mark, style: .body)))
        }

        for child in listItem.children {
            if let paragraph = child as? Paragraph {
                textRuns.append(contentsOf: paragraphRuns(from: paragraph).map { .text($0) })
            } else if child is UnorderedList || child is OrderedList {
                if !textRuns.isEmpty {
                    appendListParagraph(runs: textRuns, depth: listDepth, numId: numId)
                    textRuns = []
                }
                visit(child)
            }
        }

        if !textRuns.isEmpty {
            appendListParagraph(runs: textRuns, depth: listDepth, numId: numId)
        }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let lang = (codeBlock.language ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lang == "mermaid" {
            if consumeRaster(.mermaid) {
                return
            }
        }

        var runs: [TextRun] = []
        if !lang.isEmpty, lang != "mermaid" {
            runs.append(.init(text: "[\(lang)]\n", style: .code))
        } else if lang == "mermaid" {
            runs.append(.init(text: "[mermaid diagram]\n", style: .code))
        }
        let lines = codeBlock.code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (index, line) in lines.enumerated() {
            if index > 0 { runs.append(.init(text: "\n", style: .code, isBreak: true)) }
            runs.append(.init(text: line, style: .code))
        }
        appendCodeParagraph(runs: runs)
    }

    mutating func visitTable(_ table: Table) {
        let source = table.format()
        guard let model = TableModel.parse(source: source), !model.cells.isEmpty else { return }

        let columnCount = model.columnCount
        let colWidth = max(2400, 9000 / max(columnCount, 1))
        var xml = "<w:tbl><w:tblPr><w:tblW w:w=\"5000\" w:type=\"pct\"/><w:tblBorders>"
        for edge in ["top", "left", "bottom", "right", "insideH", "insideV"] {
            xml += "<w:\(edge) w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"AAAAAA\"/>"
        }
        xml += "</w:tblBorders></w:tblPr><w:tblGrid>"
        for _ in 0..<columnCount { xml += "<w:gridCol w:w=\"\(colWidth)\"/>" }
        xml += "</w:tblGrid>"

        for (rowIndex, row) in model.cells.enumerated() {
            guard row.contains(where: { !isBlankCell($0) }) else { continue }
            xml += "<w:tr>"
            for cell in row.prefix(columnCount) {
                let cellRuns = tableCellRuns(cell)
                let isHeader = rowIndex == 0
                xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(colWidth)\" w:type=\"dxa\"/>"
                if isHeader {
                    xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"EEF2F7\"/>"
                }
                xml += "</w:tcPr>"
                xml += paragraphXML(runs: cellRuns.map { .text($0) }, style: isHeader ? .tableHeader : .tableCell)
                xml += "</w:tc>"
            }
            xml += "</w:tr>"
        }
        xml += "</w:tbl>"
        paragraphs.append(xml)
    }

    // MARK: Raster assets

    @discardableResult
    mutating func consumeRaster(_ kind: DocxRasterAsset.Kind) -> Bool {
        guard let index = rasterQueue.firstIndex(where: { $0.kind == kind }) else { return false }
        let asset = rasterQueue.remove(at: index)
        appendImageParagraph(asset: asset, centered: true)
        return true
    }

    mutating func appendImageParagraph(asset: DocxRasterAsset, centered: Bool) {
        let docPrId = nextMediaIndex
        guard let relId = embedPNG(asset.pngData) else { return }
        let widthEmu = max(1, Int(asset.widthPx * 9525))
        let heightEmu = max(1, Int(asset.heightPx * 9525))
        let align = centered ? "<w:jc w:val=\"center\"/>" : ""
        paragraphs.append(
            """
            <w:p><w:pPr>\(align)<w:spacing w:before="120" w:after="120"/></w:pPr><w:r><w:drawing>
            <wp:inline distT="0" distB="0" distL="0" distR="0">
            <wp:extent cx="\(widthEmu)" cy="\(heightEmu)"/>
            <wp:effectExtent l="0" t="0" r="0" b="0"/>
            <wp:docPr id="\(docPrId)" name="Picture \(docPrId)"/>
            <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>
            <a:graphic>
            <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
            <pic:pic>
            <pic:nvPicPr><pic:cNvPr id="\(docPrId)" name="Picture \(docPrId)"/><pic:cNvPicPr/></pic:nvPicPr>
            <pic:blipFill><a:blip r:embed="\(relId)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
            <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(widthEmu)" cy="\(heightEmu)"/></a:xfrm>
            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
            </pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
            """
        )
    }

    mutating func embedPNG(_ data: Data) -> String? {
        let name = "image\(nextMediaIndex).png"
        nextMediaIndex += 1
        mediaFiles.append((name: "media/\(name)", data: data, contentType: "image/png"))
        let relId = "rId\(nextRelID)"
        nextRelID += 1
        relationships.append((
            id: relId,
            type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image",
            target: "media/\(name)",
            external: false
        ))
        return relId
    }

    mutating func embedFileImage(at fileURL: URL, alt: String) {
        let accessed = ImageInsertionHelper.startAccessing(url: fileURL)
        defer {
            if accessed { fileURL.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            appendParagraph(runs: [.init(text: alt.isEmpty ? fileURL.lastPathComponent : alt, style: .body.withItalic(true))], style: .body)
            return
        }

        let ext = fileURL.pathExtension.lowercased()
        let pngData: Data?
        if ext == "png" {
            pngData = data
        } else if let image = NSImage(data: data),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) {
            pngData = rep.representation(using: .png, properties: [:])
        } else {
            pngData = nil
        }

        let docPrId = nextMediaIndex
        guard let pngData, let relId = embedPNG(pngData) else {
            appendParagraph(runs: [.init(text: "[Image: \(alt.isEmpty ? fileURL.lastPathComponent : alt)]", style: .body.withItalic(true))], style: .body)
            return
        }

        var widthPx: CGFloat = 480
        var heightPx: CGFloat = 360
        if let image = NSImage(data: pngData) {
            widthPx = max(image.size.width, 120)
            heightPx = max(image.size.height, 80)
        }
        let widthEmu = max(1, Int(widthPx * 9525))
        let heightEmu = max(1, Int(heightPx * 9525))
        paragraphs.append(
            """
            <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:before="120" w:after="120"/></w:pPr><w:r><w:drawing>
            <wp:inline distT="0" distB="0" distL="0" distR="0">
            <wp:extent cx="\(widthEmu)" cy="\(heightEmu)"/>
            <wp:effectExtent l="0" t="0" r="0" b="0"/>
            <wp:docPr id="\(docPrId)" name="\(xmlEscape(alt))" descr="\(xmlEscape(alt))"/>
            <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>
            <a:graphic>
            <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
            <pic:pic>
            <pic:nvPicPr><pic:cNvPr id="\(docPrId)" name="\(xmlEscape(alt))"/><pic:cNvPicPr/></pic:nvPicPr>
            <pic:blipFill><a:blip r:embed="\(relId)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
            <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(widthEmu)" cy="\(heightEmu)"/></a:xfrm>
            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
            </pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
            """
        )
    }

    // MARK: Inline

    private mutating func paragraphRuns(from paragraph: Paragraph) -> [TextRun] {
        var runs: [TextRun] = []
        collectInline(from: paragraph, style: .body, into: &runs)
        return runs
    }

    private mutating func inlineRuns(from markup: Markup) -> [TextRun] {
        var runs: [TextRun] = []
        collectInline(from: markup, style: .body, into: &runs)
        return runs
    }

    private mutating func textRuns(from string: String, style: RunStyle = .body) -> [TextRun] {
        var runs: [TextRun] = []
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                runs.append(.init(text: "", style: style, isBreak: true))
            }
            for segment in DocxMathOMML.splitInlineMath(line) {
                switch segment {
                case .text(let value):
                    guard !value.isEmpty else { continue }
                    runs.append(.init(text: value, style: style))
                case .math(let latex):
                    if let omml = DocxMathOMML.omml(for: latex, display: false) {
                        runs.append(.init(text: "", style: style, omml: omml))
                    } else {
                        runs.append(.init(text: latex, style: .code))
                    }
                }
            }
        }
        return runs
    }

    private mutating func collectInline(from markup: Markup, style: RunStyle, into runs: inout [TextRun]) {
        switch markup {
        case let text as Text:
            runs.append(contentsOf: textRuns(from: text.string, style: style))
        case let strong as Strong:
            for child in strong.children {
                collectInline(from: child, style: style.withBold(true), into: &runs)
            }
        case let emphasis as Emphasis:
            for child in emphasis.children {
                collectInline(from: child, style: style.withItalic(true), into: &runs)
            }
        case let strike as Strikethrough:
            for child in strike.children {
                collectInline(from: child, style: style.withStrike(true), into: &runs)
            }
        case let inlineCode as InlineCode:
            runs.append(.init(text: inlineCode.code, style: .code))
        case let link as Markdown.Link:
            let linkText = plainText(of: link)
            let href = link.destination ?? linkText
            if isValidHyperlinkURL(href) {
                runs.append(.init(text: linkText, style: style, link: href))
            } else {
                runs.append(.init(text: linkText, style: style))
            }
        case is SoftBreak, is LineBreak:
            runs.append(.init(text: "", style: style, isBreak: true))
        case let inlineHTML as InlineHTML:
            let raw = inlineHTML.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.hasPrefix("<"), raw.hasSuffix(">"), !raw.contains(" ") {
                let inner = String(raw.dropFirst().dropLast())
                if inner.hasPrefix("http://") || inner.hasPrefix("https://") {
                    if isValidHyperlinkURL(inner) {
                        runs.append(.init(text: inner, style: style, link: inner))
                        return
                    }
                }
            }
            runs.append(contentsOf: textRuns(from: stripHTML(raw), style: style))
        case let image as Markdown.Image:
            runs.append(.init(text: "[Image: \(image.plainText)]", style: style.withItalic(true)))
        default:
            for child in markup.children {
                collectInline(from: child, style: style, into: &runs)
            }
        }
    }

    private func isImageOnlyParagraph(_ paragraph: Paragraph) -> Bool {
        var sawImage = false
        for child in paragraph.children {
            if child is Markdown.Image {
                sawImage = true
            } else if let text = child as? Text {
                if !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return false
                }
            } else {
                return false
            }
        }
        return sawImage
    }

    private func imageFromParagraph(_ paragraph: Paragraph) -> Markdown.Image? {
        paragraph.children.compactMap { $0 as? Markdown.Image }.first
    }

    private mutating func tableCellRuns(_ markdown: String) -> [TextRun] {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBlankCell(trimmed) else { return [.init(text: "", style: .body)] }
        let doc = Document(parsing: trimmed)
        var builder = DocxDocumentBuilder(sourceMarkdown: trimmed, documentURL: documentURL, title: title, rasterAssets: [])
        return builder.inlineRuns(from: doc)
    }

    private func resolveImageFileURL(_ rawSrc: String?) -> URL? {
        guard var src = rawSrc?.trimmingCharacters(in: .whitespacesAndNewlines), !src.isEmpty else { return nil }
        if src.hasPrefix("<") && src.hasSuffix(">") {
            src = String(src.dropFirst().dropLast())
        }
        if ImageInsertionHelper.isCustomImageURL(src), let url = URL(string: src),
           let path = ImageInsertionHelper.localPath(fromBlackBeardURL: url) {
            return URL(fileURLWithPath: path)
        }
        if src.hasPrefix("file://") {
            return URL(string: src)
        }
        if src.hasPrefix("/") {
            return URL(fileURLWithPath: src)
        }
        if let docURL = documentURL {
            let relative = src.hasPrefix("./") ? String(src.dropFirst(2)) : src
            return docURL.deletingLastPathComponent().appendingPathComponent(relative)
        }
        return nil
    }

    private func plainText(of markup: Markup) -> String {
        var parts: [String] = []
        for child in markup.children {
            if let text = child as? Text {
                parts.append(text.string)
            } else {
                parts.append(plainText(of: child))
            }
        }
        return parts.joined()
    }

    private func isBlankCell(_ text: String) -> Bool {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: XML assembly

    private enum ParagraphRun {
        case text(TextRun)
        case omml(String)
    }

    private mutating func appendParagraph(runs: [TextRun], style: ParagraphStyle) {
        appendParagraph(runs: runs.map { .text($0) }, style: style)
    }

    private mutating func appendListParagraph(runs: [ParagraphRun], depth: Int, numId: Int) {
        appendParagraph(runs: runs, style: .listItem(depth: depth, numId: numId))
    }

    private mutating func appendParagraph(runs: [ParagraphRun], style: ParagraphStyle) {
        paragraphs.append(paragraphXML(runs: runs, style: style))
    }

    private mutating func appendCodeParagraph(runs: [TextRun]) {
        paragraphs.append(codeParagraphXML(runs: runs))
    }

    private mutating func paragraphXML(runs: [ParagraphRun], style: ParagraphStyle) -> String {
        var xml = "<w:p><w:pPr>\(style.properties)"
        if case let .listItem(depth, numId) = style {
            xml += "<w:numPr><w:ilvl w:val=\"\(max(0, depth - 1))\"/><w:numId w:val=\"\(numId)\"/></w:numPr>"
        }
        xml += "</w:pPr>"

        for run in runs {
            switch run {
            case .omml(let omml):
                xml += omml
            case .text(let textRun):
                if let link = textRun.link, isValidHyperlinkURL(link) {
                    let relID = addHyperlinkRelationship(url: link)
                    guard !relID.isEmpty else {
                        xml += runXML(textRun, style: textRun.style, paragraphStyle: style)
                        continue
                    }
                    xml += "<w:hyperlink r:id=\"\(relID)\">"
                    xml += runXML(textRun, style: textRun.style.withLink(true), paragraphStyle: style)
                    xml += "</w:hyperlink>"
                } else if let omml = textRun.omml {
                    xml += "<w:r>\(omml)</w:r>"
                } else if textRun.isBreak {
                    xml += "<w:r>\(runProperties(textRun.style, paragraphStyle: style))<w:br/></w:r>"
                } else {
                    xml += runXML(textRun, style: textRun.style, paragraphStyle: style)
                }
            }
        }
        xml += "</w:p>"
        return xml
    }

    private func codeParagraphXML(runs: [TextRun]) -> String {
        var xml = "<w:p><w:pPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F3F4F6\"/><w:spacing w:before=\"120\" w:after=\"120\"/></w:pPr>"
        for run in runs {
            if run.isBreak {
                xml += "<w:r>\(runProperties(.code, paragraphStyle: .body))<w:br/></w:r>"
            } else {
                xml += runXML(run, style: .code, paragraphStyle: .body)
            }
        }
        xml += "</w:p>"
        return xml
    }

    private func runXML(_ run: TextRun, style: RunStyle, paragraphStyle: ParagraphStyle) -> String {
        "<w:r>\(runProperties(style, paragraphStyle: paragraphStyle))<w:t xml:space=\"preserve\">\(xmlEscape(run.text))</w:t></w:r>"
    }

    private func runProperties(_ style: RunStyle, paragraphStyle: ParagraphStyle = .body) -> String {
        var props = ""
        if style.bold { props += "<w:b/>" }
        if style.italic { props += "<w:i/>" }
        if style.strike { props += "<w:strike/>" }
        if style.link {
            props += "<w:rStyle w:val=\"Hyperlink\"/>"
            props += "<w:color w:val=\"0563C1\"/>"
            props += "<w:u w:val=\"single\"/>"
        }
        if style.isCode {
            props += "<w:rStyle w:val=\"CodeChar\"/>"
            props += "<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\" w:cs=\"Courier New\"/>"
            props += "<w:sz w:val=\"20\"/><w:sz-cs w:val=\"20\"/>"
            props += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F3F4F6\"/>"
        } else if let headingSize = paragraphStyle.headingFontSize {
            props += "<w:sz w:val=\"\(headingSize)\"/><w:sz-cs w:val=\"\(headingSize)\"/>"
        }
        guard !props.isEmpty else { return "" }
        return "<w:rPr>\(props)</w:rPr>"
    }

    private mutating func appendCenteredParagraph(runs: [TextRun], style: ParagraphStyle) {
        let inner = paragraphXML(runs: runs.map { .text($0) }, style: style)
        let centered = inner.replacingOccurrences(
            of: "<w:pPr>",
            with: "<w:pPr><w:jc w:val=\"center\"/><w:spacing w:before=\"120\" w:after=\"120\"/>"
        )
        paragraphs.append(centered)
    }

    private func isValidHyperlinkURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return false
        }
        guard scheme == "http" || scheme == "https" else { return false }
        return url.host != nil && !trimmed.contains(" ")
    }

    private mutating func addHyperlinkRelationship(url: String) -> String {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidHyperlinkURL(normalized) else {
            return ""
        }
        let id = "rId\(nextRelID)"
        nextRelID += 1
        relationships.append((
            id: id,
            type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",
            target: normalized,
            external: true
        ))
        return id
    }

    // MARK: Package

    mutating func write(to outputURL: URL) throws {
        let body = paragraphs.joined()
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
        <w:body>\(body)<w:sectPr/></w:body></w:document>
        """

        let relsXML = relationshipsXML()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blackbeareditor-docx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePackageFiles(documentXML: documentXML, relsXML: relsXML, in: tempDir)
        try DocxZipArchive.createArchive(from: tempDir, to: outputURL)
    }

    private func relationshipsXML() -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
        """
        for rel in relationships {
            if rel.external {
                xml += "<Relationship Id=\"\(rel.id)\" Type=\"\(rel.type)\" Target=\"\(xmlEscape(rel.target))\" TargetMode=\"External\"/>"
            } else {
                xml += "<Relationship Id=\"\(rel.id)\" Type=\"\(rel.type)\" Target=\"\(xmlEscape(rel.target))\"/>"
            }
        }
        xml += "</Relationships>"
        return xml
    }

    private func writePackageFiles(documentXML: String, relsXML: String, in root: URL) throws {
        func packageURL(_ relativePath: String) -> URL {
            root.appending(path: relativePath)
        }

        func write(_ text: String, _ relativePath: String) throws {
            let url = packageURL(relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        func writeData(_ data: Data, _ relativePath: String) throws {
            let url = packageURL(relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }

        try write(DocxPackageTemplates.contentTypes(mediaFiles: mediaFiles), "[Content_Types].xml")
        try write(DocxPackageTemplates.rootRels, "_rels/.rels")
        try write(relsXML, "word/_rels/document.xml.rels")
        try write(documentXML, "word/document.xml")
        try write(DocxPackageTemplates.styles, "word/styles.xml")
        try write(DocxPackageTemplates.settings, "word/settings.xml")
        try write(DocxPackageTemplates.numbering, "word/numbering.xml")
        try write(DocxPackageTemplates.theme, "word/theme/theme1.xml")
        try write(coreProperties(title: title), "docProps/core.xml")
        try write(DocxPackageTemplates.appProperties, "docProps/app.xml")

        for media in mediaFiles {
            try writeData(media.data, "word/\(media.name)")
        }
    }

    private func coreProperties(title: String) -> String {
        let now = ISO8601DateFormatter().string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <dc:title>\(xmlEscape(title))</dc:title>
        <dc:creator>Black Beard Editor</dc:creator>
        <cp:lastModifiedBy>Black Beard Editor</cp:lastModifiedBy>
        <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Styles

private enum ParagraphStyle {
    case body
    case heading1, heading2, heading3, heading4, heading5, heading6
    case blockquote
    case listItem(depth: Int, numId: Int)
    case tableHeader
    case tableCell

    var properties: String {
        switch self {
        case .body:
            return "<w:pStyle w:val=\"Normal\"/>"
        case .heading1:
            return "<w:pStyle w:val=\"Heading1\"/>"
        case .heading2:
            return "<w:pStyle w:val=\"Heading2\"/>"
        case .heading3:
            return "<w:pStyle w:val=\"Heading3\"/>"
        case .heading4:
            return "<w:pStyle w:val=\"Heading4\"/>"
        case .heading5:
            return "<w:pStyle w:val=\"Heading5\"/>"
        case .heading6:
            return "<w:pStyle w:val=\"Heading6\"/>"
        case .blockquote:
            return "<w:ind w:left=\"720\"/><w:pBdr><w:left w:val=\"single\" w:sz=\"12\" w:space=\"4\" w:color=\"999999\"/></w:pBdr><w:spacing w:after=\"120\"/>"
        case .listItem:
            return "<w:spacing w:after=\"60\"/>"
        case .tableHeader, .tableCell:
            return "<w:spacing w:after=\"60\"/>"
        }
    }

    var headingFontSize: Int? { nil }
}

private struct RunStyle: Equatable {
    var bold = false
    var italic = false
    var strike = false
    var link = false
    var isCode = false

    static let body = RunStyle()

    static var code: RunStyle {
        var style = RunStyle()
        style.isCode = true
        return style
    }

    func withBold(_ value: Bool) -> RunStyle {
        var copy = self
        copy.bold = value
        return copy
    }

    func withItalic(_ value: Bool) -> RunStyle {
        var copy = self
        copy.italic = value
        return copy
    }

    func withStrike(_ value: Bool) -> RunStyle {
        var copy = self
        copy.strike = value
        return copy
    }

    func withLink(_ value: Bool) -> RunStyle {
        var copy = self
        copy.link = value
        return copy
    }
}

private struct TextRun {
    var text: String
    var style: RunStyle
    var link: String?
    var omml: String?
    var isBreak = false

    init(text: String, style: RunStyle, link: String? = nil, omml: String? = nil, isBreak: Bool = false) {
        self.text = text
        self.style = style
        self.link = link
        self.omml = omml
        self.isBreak = isBreak
    }
}

// MARK: - Static OOXML parts

private enum DocxPackageTemplates {
    static func contentTypes(mediaFiles: [(name: String, data: Data, contentType: String)]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Default Extension="png" ContentType="image/png"/>
        <Override PartName="/_rels/.rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
        <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
        <Override PartName="/word/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
        <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        """
        for media in mediaFiles {
            xml += "<Override PartName=\"/word/\(media.name)\" ContentType=\"\(media.contentType)\"/>"
        }
        xml += "</Types>"
        return xml
    }

    static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
    <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """

    static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:sz-cs w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>
    <w:style w:type="paragraph" w:styleId="Normal" w:default="1"><w:name w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="120"/></w:pPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="480" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:b/><w:sz w:val="32"/><w:sz-cs w:val="32"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="360" w:after="80"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:b/><w:sz w:val="28"/><w:sz-cs w:val="28"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="280" w:after="80"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:b/><w:sz w:val="26"/><w:sz-cs w:val="26"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="heading 4"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="60"/><w:outlineLvl w:val="3"/></w:pPr><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:b/><w:sz w:val="24"/><w:sz-cs w:val="24"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading5"><w:name w:val="heading 5"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="200" w:after="60"/><w:outlineLvl w:val="4"/></w:pPr><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:b/><w:sz w:val="22"/><w:sz-cs w:val="22"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading6"><w:name w:val="heading 6"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="200" w:after="60"/><w:outlineLvl w:val="5"/></w:pPr><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:b/><w:sz w:val="20"/><w:sz-cs w:val="20"/></w:rPr></w:style>
    <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style>
    <w:style w:type="character" w:styleId="CodeChar"><w:name w:val="Code"/><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/><w:sz w:val="20"/></w:rPr></w:style>
    </w:styles>
    """

    static let settings = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
    <w:mathPr>
    <m:mathFont m:val="Cambria Math"/>
    <m:brkBin m:val="before"/>
    <m:brkBinSub m:val="--"/>
    <m:smallFrac m:val="0"/>
    <m:dispDef/>
    <m:lMargin m:val="0"/>
    <m:rMargin m:val="0"/>
    <m:defJc m:val="centerGroup"/>
    <m:wrapIndent m:val="1440"/>
    <m:intLim m:val="subSup"/>
    <m:naryLim m:val="undOvr"/>
    </w:mathPr>
    </w:settings>
    """

    static let numbering = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:abstractNum w:abstractNumId="0">
    <w:multiLevelType w:val="hybridMultilevel"/>
    <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>
    <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="◦"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="1080" w:hanging="360"/></w:pPr></w:lvl>
    <w:lvl w:ilvl="2"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="▪"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="1440" w:hanging="360"/></w:pPr></w:lvl>
    </w:abstractNum>
    <w:abstractNum w:abstractNumId="1">
    <w:multiLevelType w:val="hybridMultilevel"/>
    <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>
    <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="lowerLetter"/><w:lvlText w:val="%2."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="1080" w:hanging="360"/></w:pPr></w:lvl>
    <w:lvl w:ilvl="2"><w:start w:val="1"/><w:numFmt w:val="lowerRoman"/><w:lvlText w:val="%3."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="1440" w:hanging="360"/></w:pPr></w:lvl>
    </w:abstractNum>
    <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
    <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
    </w:numbering>
    """

    static let theme = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme"><a:themeElements><a:clrScheme name="Office"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1></a:clrScheme><a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme><a:fmtScheme name="Office"/></a:themeElements></a:theme>
    """

    static let appProperties = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
    <Application>Black Beard Editor</Application>
    </Properties>
    """
}
