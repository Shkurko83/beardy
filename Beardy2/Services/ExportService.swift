//
//  ExportService.swift
//  Beardy2
//
//  Created by Butt Simpson on 28.12.2025.
//

import Foundation
import AppKit
import WebKit

// MARK: - Export Service
class ExportService {
    
    static let shared = ExportService()
    
    private init() {}
    
    // MARK: - Export Formats
    enum ExportFormat {
        case pdf
        case html
        case docx
        case plainText
        
        var fileExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .html: return "html"
            case .docx: return "docx"
            case .plainText: return "txt"
            }
        }
        
        var displayName: String {
            switch self {
            case .pdf: return "PDF Document"
            case .html: return "HTML Document"
            case .docx: return "Word Document"
            case .plainText: return "Plain Text"
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
    
    // MARK: - Export to PDF
    func exportToPDF(
        markdown: String,
        url: URL,
        options: ExportOptions = ExportOptions(),
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        // Create HTML from markdown
        let html = generateHTMLForExport(markdown: markdown, options: options)
        
        // Create temporary HTML file
        let tempHTML = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("html")
        
        do {
            try html.write(to: tempHTML, atomically: true, encoding: .utf8)
            
            // Use WebKit to render and create PDF
            DispatchQueue.main.async {
                let webView = WKWebView(frame: CGRect(origin: .zero, size: options.paperSize.size))
                webView.loadFileURL(tempHTML, allowingReadAccessTo: tempHTML.deletingLastPathComponent())
                
                // Wait for load completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    let config = WKPDFConfiguration()
                    config.rect = CGRect(
                        x: options.margins,
                        y: options.margins,
                        width: options.paperSize.size.width - (options.margins * 2),
                        height: options.paperSize.size.height - (options.margins * 2)
                    )
                    
                    webView.createPDF(configuration: config) { result in
                        // Clean up temp file
                        try? FileManager.default.removeItem(at: tempHTML)
                        
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
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Export to HTML
    func exportToHTML(
        markdown: String,
        url: URL,
        options: ExportOptions = ExportOptions(),
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let html = generateHTMLForExport(markdown: markdown, options: options)
        
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            
            // Copy images if needed
            if options.embedImages {
                embedImagesInHTML(at: url, markdown: markdown)
            }
            
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
        // Remove markdown formatting
        let plainText = markdown.withoutMarkdown
        
        do {
            try plainText.write(to: url, atomically: true, encoding: .utf8)
            completion(.success(url))
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Generate HTML
    private func generateHTMLForExport(markdown: String, options: ExportOptions) -> String {
        let renderedMarkdown = parseMarkdownToHTML(markdown)
        let css = getExportCSS(theme: options.theme)
        let toc = options.includeTOC ? generateTableOfContents(markdown: markdown) : ""
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Exported Document</title>
            \(options.includeCSS ? "<style>\(css)</style>" : "")
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/\(options.theme).min.css">
        </head>
        <body>
            \(toc)
            <div class="markdown-body">
                \(renderedMarkdown)
            </div>
            \(options.includePageNumbers ? getPageNumbersScript() : "")
            <script>hljs.highlightAll();</script>
        </body>
        </html>
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
