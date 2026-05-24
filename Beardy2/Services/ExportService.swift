//
//  ExportService.swift
//  Beardy2
//
//  Created by Butt Simpson on 28.12.2025.
//

import Foundation
import AppKit
import WebKit
import Markdown

// MARK: - Export Service
class ExportService {
    
    static let shared = ExportService()
    
    private var activePDFSession: PDFExportSession?
    
    private init() {}
    
    // MARK: - Export Formats
    enum ExportFormat {
        case pdf
        case html
        case htmlPlain
        case plainText
        case markdown
        
        var fileExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .html, .htmlPlain: return "html"
            case .plainText: return "txt"
            case .markdown: return "md"
            }
        }
        
        var displayName: String {
            switch self {
            case .pdf: return "PDF"
            case .html: return "HTML"
            case .htmlPlain: return "HTML (without styles)"
            case .plainText: return "Plain Text"
            case .markdown: return "Markdown"
            }
        }
        
        var includesStyles: Bool {
            switch self {
            case .htmlPlain: return false
            default: return true
            }
        }
    }
    
    // MARK: - Export Options
    struct ExportOptions {
        var format: ExportFormat = .pdf
        var includeTOC: Bool = false
        var includePageNumbers: Bool = true
        var paperSize: PaperSize = .letter
        var margins: CGFloat = 72 // 1 inch in points
        var theme: String = "github"
        var includeCSS: Bool = true
        var embedImages: Bool = false
        
        enum PaperSize {
            case letter  // 8.5 x 11 inches
            case a4      // 210 x 297 mm
            case legal   // 8.5 x 14 inches
            
            var size: CGSize {
                switch self {
                case .letter:
                    return CGSize(width: 612, height: 792) // points
                case .a4:
                    return CGSize(width: 595, height: 842) // points
                case .legal:
                    return CGSize(width: 612, height: 1008) // points
                }
            }
        }
    }
    
    // MARK: - Unified export entry
    func export(
        markdown: String,
        to url: URL,
        documentURL: URL?,
        format: ExportFormat,
        options: ExportOptions = ExportOptions(),
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        var opts = options
        opts.format = format
        opts.includeCSS = format.includesStyles && options.includeCSS
        
        switch format {
        case .pdf:
            exportToPDF(markdown: markdown, url: url, documentURL: documentURL, options: opts, completion: completion)
        case .html, .htmlPlain:
            exportToHTML(markdown: markdown, url: url, documentURL: documentURL, options: opts, completion: completion)
        case .plainText:
            exportToPlainText(markdown: markdown, url: url, completion: completion)
        case .markdown:
            exportToMarkdown(markdown: markdown, url: url, completion: completion)
        }
    }
    
    // MARK: - Export to PDF
    func exportToPDF(
        markdown: String,
        url: URL,
        documentURL: URL?,
        options: ExportOptions = ExportOptions(),
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let html = generateHTMLForExport(markdown: markdown, documentURL: documentURL, options: options)
        let baseURL = documentURL?.deletingLastPathComponent()
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let session = PDFExportSession(
                html: html,
                baseURL: baseURL,
                paperSize: options.paperSize.size,
                margins: options.margins
            )
            self.activePDFSession = session
            session.renderPDF { result in
                self.activePDFSession = nil
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: url)
                        completion(.success(url))
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Export to HTML
    func exportToHTML(
        markdown: String,
        url: URL,
        documentURL: URL?,
        options: ExportOptions = ExportOptions(),
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let html = generateHTMLForExport(markdown: markdown, documentURL: documentURL, options: options)
        
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            completion(.success(url))
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Export to Plain Text
    func exportToPlainText(
        markdown: String,
        url: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let plainText = markdown.withoutMarkdown
        
        do {
            try plainText.write(to: url, atomically: true, encoding: .utf8)
            completion(.success(url))
        } catch {
            completion(.failure(error))
        }
    }
    
    func exportToMarkdown(
        markdown: String,
        url: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            completion(.success(url))
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Generate HTML
    func generateHTMLForExport(
        markdown: String,
        documentURL: URL?,
        options: ExportOptions
    ) -> String {
        let renderedMarkdown = renderMarkdownBody(markdown, documentURL: documentURL)
        let codeTheme = ThemeService.shared.currentCodeTheme
        let themedCSS = options.includeCSS ? getThemedExportCSS() : ""
        let toc = options.includeTOC ? generateTableOfContents(markdown: markdown) : ""
        let title = documentURL?.deletingPathExtension().lastPathComponent ?? "Exported Document"
        
        let hljsHead: String
        if options.includeCSS {
            hljsHead = """
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
            <link rel="stylesheet" href="\(codeTheme.cdnURL)">
            """
        } else {
            hljsHead = ""
        }
        
        let hljsScript = options.includeCSS ? "<script>hljs.highlightAll();</script>" : ""
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapeHTML(title))</title>
            \(options.includeCSS ? "<style>\(themedCSS)</style>" : "")
            \(hljsHead)
        </head>
        <body>
            \(toc)
            <article class="markdown-body" id="main-content">
                \(renderedMarkdown)
            </article>
            \(options.includePageNumbers ? getPageNumbersScript() : "")
            \(hljsScript)
        </body>
        </html>
        """
    }
    
    private func renderMarkdownBody(_ markdown: String, documentURL: URL?) -> String {
        let processed = markdown
            .components(separatedBy: .newlines)
            .map { $0.isEmpty ? "\u{00A0}" : $0 }
            .joined(separator: "\n")
        let document = Document(parsing: processed)
        var visitor = HTMLVisitor(documentURL: documentURL)
        return visitor.visit(document)
    }
    
    private func getThemedExportCSS() -> String {
        let colors = ThemeService.shared.currentTheme.colors
        let codeTheme = ThemeService.shared.currentCodeTheme
        let bg = colors.background.toHex()
        let text = colors.text.toHex()
        let secondary = colors.secondaryText.toHex()
        let heading = colors.heading.toHex()
        let link = colors.link.toHex()
        let codeBg = colors.code.toHex()
        let border = colors.border.toHex()
        let codeBlockBg = codeTheme.blockBackgroundHex
        let codeBlockBorder = border
        
        return """
        * { box-sizing: border-box; }
        @page { margin: 18mm; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
            font-size: 16px;
            line-height: 1.65;
            color: \(text);
            background: \(bg);
            max-width: 820px;
            margin: 0 auto;
            padding: 48px 40px;
        }
        h1, h2, h3, h4, h5, h6 {
            color: \(heading);
            font-weight: 600;
            line-height: 1.3;
            margin-top: 1.4em;
            margin-bottom: 0.5em;
        }
        h1 { font-size: 2em; border-bottom: 1px solid \(border); padding-bottom: 0.25em; }
        h2 { font-size: 1.5em; border-bottom: 1px solid \(border); padding-bottom: 0.2em; }
        p { margin: 0 0 1em; }
        a { color: \(link); text-decoration: none; }
        a:hover { text-decoration: underline; }
        blockquote {
            margin: 0 0 1em;
            padding: 0 1em;
            color: \(secondary);
            border-left: 4px solid \(border);
        }
        ul, ol { margin: 0 0 1em; padding-left: 2em; }
        li { margin: 0.25em 0; }
        img { max-width: 100%; height: auto; display: block; margin: 1em 0; }
        table { border-collapse: collapse; width: 100%; margin: 1em 0; }
        th, td { border: 1px solid \(border); padding: 8px 12px; text-align: left; }
        th { background: \(colors.tableHeader.toHex()); }
        code:not(pre code) {
            font-family: "SF Mono", Menlo, monospace;
            font-size: 0.9em;
            background: \(codeBg);
            padding: 0.15em 0.35em;
            border-radius: 4px;
        }
        pre {
            background: \(codeBlockBg) !important;
            border: 1px solid \(codeBlockBorder);
            border-radius: 8px;
            padding: 16px;
            overflow-x: auto;
            margin: 1em 0;
        }
        pre code {
            font-family: "SF Mono", Menlo, monospace;
            font-size: 13px;
            line-height: 1.5;
            white-space: pre;
            background: transparent !important;
            padding: 0 !important;
        }
        hr { border: none; border-top: 1px solid \(border); margin: 2em 0; }
        .toc {
            background: \(codeBg);
            padding: 20px 24px;
            border-radius: 8px;
            margin-bottom: 2em;
            border: 1px solid \(border);
        }
        .toc ul { list-style: none; padding-left: 0; }
        .toc a { color: \(link); }
        @media print {
            body { padding: 0; max-width: none; }
            .toc { page-break-after: always; }
            pre { page-break-inside: avoid; }
        }
        """
    }
    
    // MARK: - Parse Markdown to HTML
    private func parseMarkdownToHTML(_ markdown: String) -> String {
        var html = ""
        let lines = markdown.components(separatedBy: .newlines)
        var inCodeBlock = false
        var codeBlockLanguage = ""
        var codeBlockContent = ""
        var inList = false
        var inOrderedList = false
        var inBlockquote = false
        var blockquoteContent = ""
        
        for line in lines {
            // Code blocks
            if line.hasPrefix("```") {
                if inCodeBlock {
                    html += "<pre><code class=\"language-\(codeBlockLanguage)\">\(escapeHTML(codeBlockContent))</code></pre>\n"
                    inCodeBlock = false
                    codeBlockLanguage = ""
                    codeBlockContent = ""
                } else {
                    inCodeBlock = true
                    codeBlockLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            
            if inCodeBlock {
                codeBlockContent += line + "\n"
                continue
            }
            
            // Blockquotes
            if line.hasPrefix(">") {
                if !inBlockquote {
                    inBlockquote = true
                    blockquoteContent = ""
                }
                blockquoteContent += line.dropFirst(1).trimmingCharacters(in: .whitespaces) + "\n"
                continue
            } else if inBlockquote {
                html += "<blockquote>\(parseInlineMarkdown(blockquoteContent))</blockquote>\n"
                inBlockquote = false
                blockquoteContent = ""
            }
            
            // Horizontal rules
            if line.trimmingCharacters(in: .whitespaces).range(of: "^([-*_]\\s*){3,}$", options: .regularExpression) != nil {
                html += "<hr>\n"
                continue
            }
            
            // Headings
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let content = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                let id = content.lowercased().replacingOccurrences(of: " ", with: "-")
                html += "<h\(level) id=\"\(id)\">\(parseInlineMarkdown(content))</h\(level)>\n"
                continue
            }
            
            // Unordered lists
            if line.range(of: "^\\s*[-*+]\\s+", options: .regularExpression) != nil {
                if !inList {
                    html += "<ul>\n"
                    inList = true
                }
                let content = line.replacingOccurrences(of: "^\\s*[-*+]\\s+", with: "", options: .regularExpression)
                
                // Task list
                if content.hasPrefix("[ ] ") || content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
                    let checked = content.hasPrefix("[x] ") || content.hasPrefix("[X] ")
                    let taskContent = content.dropFirst(4)
                    html += "<li class=\"task-list-item\"><input type=\"checkbox\" \(checked ? "checked" : "") disabled> \(parseInlineMarkdown(String(taskContent)))</li>\n"
                } else {
                    html += "<li>\(parseInlineMarkdown(content))</li>\n"
                }
                continue
            } else if inList {
                html += "</ul>\n"
                inList = false
            }
            
            // Ordered lists
            if line.range(of: "^\\s*\\d+\\.\\s+", options: .regularExpression) != nil {
                if !inOrderedList {
                    html += "<ol>\n"
                    inOrderedList = true
                }
                let content = line.replacingOccurrences(of: "^\\s*\\d+\\.\\s+", with: "", options: .regularExpression)
                html += "<li>\(parseInlineMarkdown(content))</li>\n"
                continue
            } else if inOrderedList {
                html += "</ol>\n"
                inOrderedList = false
            }
            
            // Empty lines
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if inList { html += "</ul>\n"; inList = false }
                if inOrderedList { html += "</ol>\n"; inOrderedList = false }
                continue
            }
            
            // Paragraphs
            html += "<p>\(parseInlineMarkdown(line))</p>\n"
        }
        
        // Close open tags
        if inCodeBlock {
            html += "<pre><code class=\"language-\(codeBlockLanguage)\">\(escapeHTML(codeBlockContent))</code></pre>\n"
        }
        if inList { html += "</ul>\n" }
        if inOrderedList { html += "</ol>\n" }
        if inBlockquote {
            html += "<blockquote>\(parseInlineMarkdown(blockquoteContent))</blockquote>\n"
        }
        
        return html
    }
    
    // MARK: - Parse Inline Markdown
    private func parseInlineMarkdown(_ text: String) -> String {
        var result = text
        
        // Images
        result = result.replacingOccurrences(
            of: "!\\[([^\\]]*)\\]\\(([^\\)]*)\\)",
            with: "<img src=\"$2\" alt=\"$1\">",
            options: .regularExpression
        )
        
        // Links
        result = result.replacingOccurrences(
            of: "\\[([^\\]]*)\\]\\(([^\\)]*)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )
        
        // Bold
        result = result.replacingOccurrences(
            of: "\\*\\*([^*]+)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "__([^_]+)__",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        
        // Italic
        result = result.replacingOccurrences(
            of: "\\*([^*]+)\\*",
            with: "<em>$1</em>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "_([^_]+)_",
            with: "<em>$1</em>",
            options: .regularExpression
        )
        
        // Strikethrough
        result = result.replacingOccurrences(
            of: "~~([^~]+)~~",
            with: "<del>$1</del>",
            options: .regularExpression
        )
        
        // Inline code
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "<code>$1</code>",
            options: .regularExpression
        )
        
        return result
    }
    
    // MARK: - Generate Table of Contents
    private func generateTableOfContents(markdown: String) -> String {
        let headers = markdown.extractHeaders()
        
        guard !headers.isEmpty else { return "" }
        
        var toc = "<nav class=\"toc\"><h2>Table of Contents</h2><ul>"
        
        for header in headers {
            let id = header.text.lowercased().replacingOccurrences(of: " ", with: "-")
            let indent = String(repeating: "  ", count: header.level - 1)
            toc += "\(indent)<li><a href=\"#\(id)\">\(header.text)</a></li>\n"
        }
        
        toc += "</ul></nav>\n"
        
        return toc
    }
    
    // MARK: - Get Export CSS
    private func getExportCSS(theme: String) -> String {
        return """
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            font-size: 16px;
            line-height: 1.6;
            color: #24292e;
            padding: 40px;
            max-width: 800px;
            margin: 0 auto;
        }
        
        h1, h2, h3, h4, h5, h6 {
            margin-top: 24px;
            margin-bottom: 16px;
            font-weight: 600;
            line-height: 1.25;
        }
        
        h1 { font-size: 2em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
        h2 { font-size: 1.5em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
        h3 { font-size: 1.25em; }
        
        p { margin-bottom: 16px; }
        
        code {
            padding: 0.2em 0.4em;
            background-color: #f6f8fa;
            border-radius: 6px;
            font-family: 'SF Mono', Monaco, monospace;
            font-size: 85%;
        }
        
        pre {
            padding: 16px;
            overflow: auto;
            background-color: #f6f8fa;
            border-radius: 6px;
            margin-bottom: 16px;
        }
        
        pre code {
            background: transparent;
            padding: 0;
        }
        
        blockquote {
            padding: 0 1em;
            color: #6a737d;
            border-left: 0.25em solid #dfe2e5;
            margin-bottom: 16px;
        }
        
        ul, ol {
            padding-left: 2em;
            margin-bottom: 16px;
        }
        
        img {
            max-width: 100%;
            height: auto;
            margin: 16px 0;
        }
        
        .toc {
            background: #f6f8fa;
            padding: 20px;
            border-radius: 6px;
            margin-bottom: 30px;
        }
        
        .toc h2 {
            margin-top: 0;
            font-size: 1.2em;
        }
        
        .toc ul {
            list-style: none;
            padding-left: 0;
        }
        
        .toc li {
            margin: 8px 0;
        }
        
        .toc a {
            color: #0366d6;
            text-decoration: none;
        }
        
        @media print {
            body { padding: 0; }
            .toc { page-break-after: always; }
        }
        """
    }
    
    // MARK: - Page Numbers Script
    private func getPageNumbersScript() -> String {
        return """
        <script>
        window.addEventListener('load', function() {
            const pages = document.querySelectorAll('body');
            pages.forEach((page, index) => {
                const pageNumber = document.createElement('div');
                pageNumber.style.position = 'fixed';
                pageNumber.style.bottom = '20px';
                pageNumber.style.right = '20px';
                pageNumber.style.fontSize = '12px';
                pageNumber.style.color = '#666';
                pageNumber.textContent = 'Page ' + (index + 1);
                page.appendChild(pageNumber);
            });
        });
        </script>
        """
    }
    
    // MARK: - Embed Images
    private func embedImagesInHTML(at url: URL, markdown: String) {
        let images = markdown.extractImages()
        
        // Convert images to base64 and embed
        for image in images {
            if let imageURL = URL(string: image.url),
               let imageData = try? Data(contentsOf: imageURL) {
                let base64 = imageData.base64EncodedString()
                let mimeType = getMimeType(for: imageURL.pathExtension)
                let dataURL = "data:\(mimeType);base64,\(base64)"
                
                // Replace in HTML
                // This is simplified - in production you'd need proper HTML parsing
            }
        }
    }
    
    // MARK: - Helper Methods
    private func escapeHTML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    
    private func getMimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - PDF export via WebKit
private final class PDFExportSession: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let margins: CGFloat
    private let paperSize: CGSize
    private var pdfCompletion: ((Result<Data, Error>) -> Void)?
    private var didFinishLoad = false
    
    init(html: String, baseURL: URL?, paperSize: CGSize, margins: CGFloat) {
        self.margins = margins
        self.paperSize = paperSize
        
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(ImageSchemeHandler(), forURLScheme: "beardy")
        webView = WKWebView(frame: CGRect(origin: .zero, size: paperSize), configuration: config)
        
        super.init()
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: baseURL)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.finishLoadingIfNeeded()
        }
    }
    
    func renderPDF(completion: @escaping (Result<Data, Error>) -> Void) {
        pdfCompletion = completion
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoadingIfNeeded()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let pdfCompletion else { return }
        self.pdfCompletion = nil
        pdfCompletion(.failure(error))
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let pdfCompletion else { return }
        self.pdfCompletion = nil
        pdfCompletion(.failure(error))
    }
    
    private func finishLoadingIfNeeded() {
        guard !didFinishLoad, pdfCompletion != nil else { return }
        didFinishLoad = true
        
        let config = WKPDFConfiguration()
        config.rect = CGRect(
            x: margins,
            y: margins,
            width: paperSize.width - margins * 2,
            height: paperSize.height - margins * 2
        )
        
        webView.createPDF(configuration: config) { [weak self] result in
            guard let completion = self?.pdfCompletion else { return }
            self?.pdfCompletion = nil
            completion(result)
        }
    }
}
