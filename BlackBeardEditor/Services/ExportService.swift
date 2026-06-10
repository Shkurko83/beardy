//
//  ExportService.swift
//  BlackBeardEditor
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
    private var activeDocxSession: DocxExportSession?
    
    private init() {}
    
    // MARK: - Export Formats
    enum ExportFormat {
        case pdf
        case html
        case htmlPlain
        case docx
        case odt
        case rtf
        case epub
        case latex
        case plainText
        case markdown
        
        var fileExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .html, .htmlPlain: return "html"
            case .docx: return "docx"
            case .odt: return "odt"
            case .rtf: return "rtf"
            case .epub: return "epub"
            case .latex: return "tex"
            case .plainText: return "txt"
            case .markdown: return "md"
            }
        }
        
        var displayName: String {
            switch self {
            case .pdf: return "PDF"
            case .html: return "HTML"
            case .htmlPlain: return "HTML (without styles)"
            case .docx: return "Word (.docx)"
            case .odt: return "OpenDocument (.odt)"
            case .rtf: return "RTF"
            case .epub: return "EPUB"
            case .latex: return "LaTeX"
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
        
        /// Uses macOS textutil (HTML → Office formats). DOCX uses native writer instead.
        var usesTextUtil: Bool {
            switch self {
            case .odt, .rtf: return true
            default: return false
            }
        }
        
        /// Uses Pandoc when installed (preferred for DOCX if available).
        var usesPandoc: Bool {
            switch self {
            case .docx, .epub, .latex: return true
            default: return false
            }
        }
    }
    
    // MARK: - Export Options
    struct ExportOptions {
        var format: ExportFormat = .pdf
        var includeTOC: Bool = false
        var includePageNumbers: Bool = false
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
            
            var pageSizeCSS: String {
                switch self {
                case .letter: return "letter"
                case .a4: return "A4"
                case .legal: return "legal"
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
        case .docx:
            exportToDOCX(markdown: markdown, url: url, documentURL: documentURL, options: opts, completion: completion)
        case .odt, .rtf:
            exportViaTextUtil(markdown: markdown, url: url, documentURL: documentURL, options: opts, completion: completion)
        case .epub:
            exportToEPUB(markdown: markdown, url: url, completion: completion)
        case .latex:
            exportToLaTeX(markdown: markdown, url: url, completion: completion)
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let html = self.buildPreparedHTML(
                markdown: markdown,
                documentURL: documentURL,
                options: options,
                forPDF: true
            )
            let baseURL = documentURL?.deletingLastPathComponent()
            
            DispatchQueue.main.async {
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
    }
    
    // MARK: - Export to HTML
    func exportToHTML(
        markdown: String,
        url: URL,
        documentURL: URL?,
        options: ExportOptions = ExportOptions(),
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let html = self.buildPreparedHTML(
                markdown: markdown,
                documentURL: documentURL,
                options: options,
                forPDF: false
            )
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func exportViaTextUtil(
        markdown: String,
        url: URL,
        documentURL: URL?,
        options: ExportOptions,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let textUtilFormat: String
        switch options.format {
        case .odt: textUtilFormat = "odt"
        case .rtf: textUtilFormat = "rtf"
        default:
            completion(.failure(ExportError.unsupportedFormat))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let html = self.buildOfficeHTML(
                markdown: markdown,
                documentURL: documentURL,
                options: options
            )
            do {
                try TextUtilConverter.convert(html: html, to: url, format: textUtilFormat)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func exportToDOCX(
        markdown: String,
        url: URL,
        documentURL: URL?,
        options: ExportOptions,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let title = documentURL?.deletingPathExtension().lastPathComponent ?? "Exported Document"
        let usePandoc = UserDefaults.standard.bool(forKey: AppConstants.Keys.usePandocForDocxExport)

        if usePandoc && PandocConverter.isAvailable {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try PandocConverter.convert(
                        markdown: markdown,
                        to: url,
                        format: "docx",
                        resourcePath: documentURL?.deletingLastPathComponent()
                    )
                    completion(.success(url))
                } catch {
                    completion(.failure(error))
                }
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeDocxSession = DocxExportSession(
                markdown: markdown,
                documentURL: documentURL,
                outputURL: url,
                title: title
            ) { [weak self] result in
                self?.activeDocxSession = nil
                completion(result)
            }
        }
    }

    /// Full export HTML (KaTeX + Mermaid + themed CSS) for DOCX raster capture.
    func preparedHTMLForDocxExport(markdown: String, documentURL: URL?) -> String {
        var options = ExportOptions()
        options.includeCSS = true
        options.format = .docx
        return buildPreparedHTML(
            markdown: markdown,
            documentURL: documentURL,
            options: options,
            forPDF: false
        )
    }

    /// Semantic HTML for textutil (no JS/CSS). Better than full export HTML, but still limited.
    private func buildOfficeHTML(
        markdown: String,
        documentURL: URL?,
        options: ExportOptions
    ) -> String {
        let renderedMarkdown = renderMarkdownBodyForOffice(markdown, documentURL: documentURL)
        let title = documentURL?.deletingPathExtension().lastPathComponent ?? "Exported Document"
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>\(escapeHTML(title))</title>
        </head>
        <body>
            \(renderedMarkdown)
        </body>
        </html>
        """
    }

    private func renderMarkdownBodyForOffice(_ markdown: String, documentURL: URL?) -> String {
        let document = Document(parsing: markdown)
        var visitor = HTMLVisitor(sourceMarkdown: markdown, documentURL: documentURL)
        return visitor.visit(document)
    }
    
    func exportToEPUB(
        markdown: String,
        url: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try PandocConverter.exportEPUB(markdown: markdown, to: url)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func exportToLaTeX(
        markdown: String,
        url: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try PandocConverter.convert(markdown: markdown, to: url, format: "latex")
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
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
    
    private func buildPreparedHTML(
        markdown: String,
        documentURL: URL?,
        options: ExportOptions,
        forPDF: Bool
    ) -> String {
        var html = generateHTMLForExport(
            markdown: markdown,
            documentURL: documentURL,
            options: options,
            forPDF: forPDF
        )
        html = embedLocalImages(in: html)
        if options.includeCSS {
            let theme = ThemeService.shared.currentCodeTheme
            if let hljsCSS = BundledHighlightJS.loadThemeCSS(for: theme) {
                html = injectCSS(hljsCSS, into: html)
            }
            if let katexCSS = BundledKaTeX.loadCSS() {
                html = injectCSS(katexCSS, into: html)
            }
            if let hljsJS = BundledHighlightJS.loadScriptSource() {
                html = injectScript(hljsJS, into: html, beforeClosingHead: true)
            }
            if let katexJS = BundledKaTeX.loadScriptSource() {
                html = injectScript(katexJS, into: html, beforeClosingHead: true)
            }
            if let mermaidJS = BundledMermaid.loadScriptSource() {
                html = injectScript(mermaidJS, into: html, beforeClosingHead: true)
            }
        }
        return html
    }
    
    func generateHTMLForExport(
        markdown: String,
        documentURL: URL?,
        options: ExportOptions,
        forPDF: Bool = false
    ) -> String {
        let renderedMarkdown = renderMarkdownBody(markdown, documentURL: documentURL)
        let themedCSS = options.includeCSS ? getThemedExportCSS(forPDF: forPDF, options: options) : ""
        let toc = options.includeTOC ? generateTableOfContents(markdown: markdown) : ""
        let title = documentURL?.deletingPathExtension().lastPathComponent ?? "Exported Document"
        let highlightScript = options.includeCSS ? exportCodeHighlightScript : ""
        let mathScript = options.includeCSS ? exportMathTypesetScript : ""
        let isDark = ThemeService.shared.isDarkMode
        let bodyClass = isDark ? " class=\"dark\"" : ""
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapeHTML(title))</title>
            \(options.includeCSS ? "<style>\(themedCSS)</style>" : "")
        </head>
        <body\(bodyClass)>
            \(toc)
            <article class="markdown-body" id="main-content">
                \(renderedMarkdown)
            </article>
            \(mathScript)
            \(highlightScript)
            \(options.includeCSS ? exportMermaidRenderScript(isDark: isDark) : "")
        </body>
        </html>
        """
    }
    
    /// KaTeX: инлайн `$...$`, блоки `$$...$$` (в т.ч. многострочные через отдельные абзацы).
    private var exportMathTypesetScript: String {
        """
        <script>
        (function() {
            function renderExportLatex(latex, displayMode) {
                if (typeof katex === 'undefined') return null;
                try {
                    return katex.renderToString(latex, {
                        displayMode: !!displayMode,
                        throwOnError: false,
                        strict: 'ignore',
                        trust: true,
                        output: 'html'
                    });
                } catch (e) {
                    return null;
                }
            }

            function applyExportMathToHtml(html) {
                const mathPh = [];
                const codePh = [];
                let s = html || '';
                s = s.replace(/<code[^>]*>[\\s\\S]*?<\\/code>/gi, function(m) {
                    codePh.push(m);
                    return '\\x00CODE' + (codePh.length - 1) + '\\x00';
                });
                s = s.replace(/\\$\\$([\\s\\S]+?)\\$\\$/g, function(match, latex) {
                    const out = renderExportLatex(latex, true);
                    if (!out) return match;
                    mathPh.push('<span class="math-display math-inline-block">' + out + '</span>');
                    return '\\x00MATH' + (mathPh.length - 1) + '\\x00';
                });
                s = s.replace(/(^|[^\\\\$])\\$(?!\\$)((?:\\\\.|[^$\\n\\\\])+?)\\$(?!\\$)/g, function(match, prefix, latex) {
                    const out = renderExportLatex(latex, false);
                    if (!out) return match;
                    mathPh.push('<span class="math-inline">' + out + '</span>');
                    return prefix + '\\x00MATH' + (mathPh.length - 1) + '\\x00';
                });
                s = s.replace(/\\\\\\(([\\s\\S]+?)\\\\\\)/g, function(match, latex) {
                    const out = renderExportLatex(latex, false);
                    if (!out) return match;
                    mathPh.push('<span class="math-inline">' + out + '</span>');
                    return '\\x00MATH' + (mathPh.length - 1) + '\\x00';
                });
                s = s.replace(/\\\\\\[([\\s\\S]+?)\\\\\\]/g, function(match, latex) {
                    const out = renderExportLatex(latex, true);
                    if (!out) return match;
                    mathPh.push('<span class="math-display math-inline-block">' + out + '</span>');
                    return '\\x00MATH' + (mathPh.length - 1) + '\\x00';
                });
                s = s.replace(/\\x00CODE(\\d+)\\x00/g, function(_, i) { return codePh[+i] || ''; });
                s = s.replace(/\\x00MATH(\\d+)\\x00/g, function(_, i) { return mathPh[+i] || ''; });
                return s;
            }

            function isLikelyLatexLine(t) {
                return /^\\\\[a-zA-Z@]/.test((t || '').trim());
            }

            function mergeLatexOnlyParagraphs(root) {
                while (true) {
                    const paras = root.querySelectorAll('p');
                    let found = false;
                    for (let i = 0; i < paras.length; i++) {
                        const t = paras[i].textContent.trim();
                        if (!isLikelyLatexLine(t)) continue;
                        const parts = [t];
                        let j = i + 1;
                        while (j < paras.length && isLikelyLatexLine(paras[j].textContent.trim())) {
                            parts.push(paras[j].textContent.trim());
                            j++;
                        }
                        const html = renderExportLatex(parts.join('\\n'), true);
                        if (html) {
                            for (let k = j - 1; k > i; k--) paras[k].remove();
                            paras[i].outerHTML = '<div class="math-display">' + html + '</div>';
                            found = true;
                            break;
                        }
                    }
                    if (!found) break;
                }
            }

            function mergeBlockMathParagraphs(root) {
                while (true) {
                    const paras = root.querySelectorAll('p');
                    let found = false;
                    for (let i = 0; i < paras.length; i++) {
                        const p = paras[i];
                        if (p.closest('pre')) continue;
                        const t = p.textContent.trim();
                        if (t.startsWith('$$') && t.endsWith('$$') && t.length > 4) {
                            const html = renderExportLatex(t.slice(2, -2).trim(), true);
                            if (html) {
                                p.outerHTML = '<div class="math-display">' + html + '</div>';
                                found = true;
                                break;
                            }
                        }
                        if (t === '$$') {
                            const parts = [];
                            let j = i + 1;
                            while (j < paras.length && paras[j].textContent.trim() !== '$$') {
                                parts.push(paras[j].textContent);
                                j++;
                            }
                            if (j < paras.length) {
                                const html = renderExportLatex(parts.join('\\n'), true);
                                if (html) {
                                    for (let k = j; k > i; k--) paras[k].remove();
                                    p.outerHTML = '<div class="math-display">' + html + '</div>';
                                    found = true;
                                    break;
                                }
                            }
                        }
                    }
                    if (!found) break;
                }
            }

            function typesetExportMath(root) {
                if (!root || typeof katex === 'undefined') return;
                mergeLatexOnlyParagraphs(root);
                mergeBlockMathParagraphs(root);
                root.querySelectorAll('p, li, td, th, blockquote, h1, h2, h3, h4, h5, h6').forEach(function(el) {
                    if (el.closest('pre, code')) return;
                    if (el.classList.contains('math-display')) return;
                    if (!/\\$|\\\\\\(|\\\\\\[/.test(el.innerHTML)) return;
                    const next = applyExportMathToHtml(el.innerHTML);
                    if (next !== el.innerHTML) el.innerHTML = next;
                });
            }

            window.typesetExportMath = typesetExportMath;

            function runExportMath() {
                typesetExportMath(document.querySelector('.markdown-body') || document.body);
            }
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', runExportMath);
            } else {
                runExportMath();
            }
        })();
        </script>
        """
    }

    /// Mermaid: блоки ```mermaid из Swift-Markdown (code.language-mermaid).
    private func exportMermaidRenderScript(isDark: Bool) -> String {
        let theme = isDark ? "dark" : "default"
        return """
        <script>
        (function() {
            async function renderExportMermaid() {
                if (typeof mermaid === 'undefined') return;
                const root = document.querySelector('.markdown-body') || document.body;
                const codes = Array.from(root.querySelectorAll('pre code.language-mermaid, pre code.mermaid'));
                if (!codes.length) return;
                const nodes = [];
                codes.forEach(function(code) {
                    const pre = code.closest('pre');
                    if (!pre) return;
                    const src = (code.textContent || '').trim();
                    const div = document.createElement('div');
                    div.className = 'mermaid mermaid-diagram export-mermaid';
                    div.setAttribute('data-mermaid-source', src);
                    div.textContent = src;
                    pre.replaceWith(div);
                    nodes.push(div);
                });
                try {
                    mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: '\(theme)' });
                    await mermaid.run({ nodes: nodes });
                } catch (e) {
                    nodes.forEach(function(n) {
                        n.innerHTML = '<pre class="mermaid-error">' + (e.message || String(e)) + '</pre>';
                    });
                }
            }
            window.renderExportMermaid = renderExportMermaid;
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', renderExportMermaid);
            } else {
                renderExportMermaid();
            }
        })();
        </script>
        """
    }

    /// Подсветка как в Preview/Live: без нумерации строк.
    private var exportCodeHighlightScript: String {
        """
        <script>
        (function() {
            function applyExportHighlight() {
                if (typeof hljs === 'undefined') return;
                document.querySelectorAll('pre code').forEach(function(block) {
                    if (block.closest('table.hljs-ln')) return;
                    if (block.classList.contains('language-mermaid') || block.classList.contains('mermaid')) return;
                    hljs.highlightElement(block);
                    var pre = block.closest('pre');
                    if (pre) pre.classList.add('hljs');
                });
                document.querySelectorAll('table.hljs-ln').forEach(function(t) { t.remove(); });
            }
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', applyExportHighlight);
            } else {
                applyExportHighlight();
            }
        })();
        </script>
        """
    }
    
    private func injectCSS(_ extraCSS: String, into html: String) -> String {
        guard !extraCSS.isEmpty else { return html }
        if html.contains("</style>") {
            return html.replacingOccurrences(of: "</style>", with: "\n\(extraCSS)\n</style>")
        }
        return html.replacingOccurrences(
            of: "</head>",
            with: "<style>\(extraCSS)</style>\n</head>"
        )
    }
    
    private func injectScript(_ script: String, into html: String, beforeClosingHead: Bool) -> String {
        guard !script.isEmpty else { return html }
        let tag = "<script>\n\(script)\n</script>"
        if beforeClosingHead, html.contains("</head>") {
            return html.replacingOccurrences(of: "</head>", with: "\(tag)\n</head>")
        }
        if html.contains("</body>") {
            return html.replacingOccurrences(of: "</body>", with: "\(tag)\n</body>")
        }
        return html + tag
    }
    
    private func embedLocalImages(in html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(<img[^>]*\ssrc=)(["'])([^"']+)\2"#,
            options: [.caseInsensitive]
        ) else { return html }
        
        let nsHTML = html as NSString
        var result = html
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).reversed()
        
        for match in matches {
            let prefix = nsHTML.substring(with: match.range(at: 1))
            let quote = nsHTML.substring(with: match.range(at: 2))
            let src = nsHTML.substring(with: match.range(at: 3))
            
            if src.hasPrefix("data:") { continue }
            
            guard let dataURL = imageDataURL(for: src) else { continue }
            let replacement = "\(prefix)\(quote)\(dataURL)\(quote)"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        
        return result
    }
    
    private func imageDataURL(for src: String) -> String? {
        let filePath: String?
        
        if ImageInsertionHelper.isCustomImageURL(src), let url = URL(string: src) {
            filePath = ImageInsertionHelper.localPath(fromBlackBeardURL: url)
        } else if src.hasPrefix("file://") {
            filePath = URL(string: src)?.path
        } else if src.hasPrefix("/") {
            filePath = src
        } else {
            filePath = nil
        }
        
        guard let filePath else { return nil }
        let fileURL = URL(fileURLWithPath: filePath)
        
        let accessed = ImageInsertionHelper.startAccessing(url: fileURL)
        defer {
            if accessed { fileURL.stopAccessingSecurityScopedResource() }
        }
        
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let mime = mimeType(for: fileURL.pathExtension)
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
    
    private func renderMarkdownBody(_ markdown: String, documentURL: URL?) -> String {
        let processed = markdown
            .components(separatedBy: .newlines)
            .map { $0.isEmpty ? "\u{00A0}" : $0 }
            .joined(separator: "\n")
        let document = Document(parsing: processed)
        var visitor = HTMLVisitor(sourceMarkdown: markdown, documentURL: documentURL)
        return visitor.visit(document)
    }
    
    private func getThemedExportCSS(forPDF: Bool, options: ExportOptions) -> String {
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
        let marginPt = max(Int(options.margins), 54)
        let pageSize = options.paperSize.pageSizeCSS
        
        let bodyLayout: String
        let pageRule: String
        if forPDF {
            // Размер страницы для печати; поля — через NSPrintInfo при экспорте PDF.
            pageRule = "@page { size: \(pageSize); margin: \(marginPt)pt; }"
            bodyLayout = """
            html, body {
                width: 100%;
                margin: 0;
                padding: 0;
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                font-size: 16px;
                line-height: 1.65;
                color: \(text);
                background: \(bg);
                max-width: none;
                box-sizing: border-box;
            }
            .markdown-body {
                max-width: none;
                margin: 0;
                padding: 0;
            }
            html, body, .markdown-body, article {
                height: auto !important;
                min-height: 0 !important;
                max-height: none !important;
                overflow: visible !important;
            }
            pre, pre.hljs {
                max-height: none !important;
                overflow: visible !important;
                page-break-inside: avoid;
            }
            details {
                display: block !important;
                overflow: visible !important;
            }
            details > summary {
                display: block !important;
            }
            details[open] > :not(summary),
            details.export-open > :not(summary) {
                display: block !important;
            }
            """
        } else {
            pageRule = ""
            bodyLayout = """
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
            """
        }
        
        return """
        * { box-sizing: border-box; }
        \(pageRule)
        \(bodyLayout)
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
        ul { margin: 0 0 1em; padding-left: 2em; list-style-type: disc; }
        ul ul { list-style-type: disc; }
        ol { margin: 0 0 1em; padding-left: 2em; list-style-type: decimal; }
        ol ol { list-style-type: decimal; }
        li { margin: 0.25em 0; }
        li > ul, li > ol { margin-top: 0.25em; margin-bottom: 0.35em; }
        ul.task-list, ol.task-list { list-style: none; padding-left: 2em; }
        ul.task-list ul.task-list { padding-left: 2em; margin-left: 0; }
        li.task-list-item, .task-list > li {
            display: block;
            list-style: none;
        }
        .task-list-item-main {
            display: flex;
            align-items: flex-start;
            gap: 8px;
        }
        sub, sup {
            font-size: 0.75em;
            line-height: 0;
            position: relative;
            vertical-align: baseline;
        }
        sup { top: -0.4em; }
        sub { bottom: -0.2em; }
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
        pre,
        pre.hljs {
            background: \(codeBlockBg) !important;
            border: 1px solid \(codeBlockBorder);
            border-radius: 8px;
            padding: 14px 16px !important;
            overflow-x: auto;
            margin: 1em 0;
        }
        pre code,
        pre code.hljs,
        pre .hljs {
            font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
            font-size: 13px;
            line-height: 1.5;
            white-space: pre;
            display: block;
            background: transparent !important;
            background-color: transparent !important;
            padding: 0 !important;
        }
        pre code.hljs *,
        pre .hljs * {
            background: transparent !important;
            background-color: transparent !important;
        }
        table.hljs-ln {
            display: none !important;
        }
        hr { border: none; border-top: 1px solid \(border); margin: 2em 0; }
        .math-display {
            margin: 1em 0;
            overflow-x: auto;
            text-align: center;
        }
        .math-display > .katex-display { margin: 0; }
        .math-inline .katex { font-size: 1.05em; }
        .katex-mathml {
            position: absolute;
            clip: rect(1px, 1px, 1px, 1px);
            height: 1px;
            width: 1px;
            overflow: hidden;
            padding: 0;
            border: 0;
        }
        .mermaid-diagram, .export-mermaid {
            margin: 1em 0;
            text-align: center;
            overflow-x: auto;
        }
        .mermaid-diagram svg { max-width: 100%; height: auto; }
        .mermaid-error { color: \(secondary); font-family: monospace; font-size: 12px; }
        \(ThemeService.shared.isDarkMode ? mermaidDarkExportCSS(text: text, secondary: secondary) : "")
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
            .toc { page-break-after: always; }
            pre, pre.hljs { page-break-inside: avoid; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
            img { page-break-inside: avoid; }
        }
        """
    }

    /// Fallback CSS so Mermaid edges/labels stay visible when the dark theme SVG still uses dark strokes.
    private func mermaidDarkExportCSS(text: String, secondary: String) -> String {
        """
        .mermaid-diagram svg .edgePath .path,
        .mermaid-diagram svg path.flowchart-link,
        .mermaid-diagram svg .flowchart-link {
            stroke: \(text) !important;
        }
        .mermaid-diagram svg marker path,
        .mermaid-diagram svg .arrowheadPath {
            fill: \(text) !important;
            stroke: \(text) !important;
        }
        .mermaid-diagram svg .edgeLabel text {
            fill: \(secondary) !important;
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
    
    // MARK: - Embed Images
    private func embedImagesInHTML(at url: URL, markdown: String) {
        let images = markdown.extractImages()
        
        // Convert images to base64 and embed
        for image in images {
            if let imageURL = URL(string: image.url),
               let imageData = try? Data(contentsOf: imageURL) {
                let base64 = imageData.base64EncodedString()
                let mimeType = mimeType(for: imageURL.pathExtension)
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
    
    private func mimeType(for fileExtension: String) -> String {
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

// MARK: - PDF export via WebKit (NSPrintOperation modal — постраничная печать, без run())
private final class PDFExportSession: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let hostWindow: NSWindow
    private let paperSize: CGSize
    private let margins: CGFloat
    private var pdfCompletion: ((Result<Data, Error>) -> Void)?
    private var savePDFURL: URL?
    private var didStartRender = false
    
    init(html: String, baseURL: URL?, paperSize: CGSize, margins: CGFloat) {
        self.paperSize = paperSize
        self.margins = margins
        
        let config = WKWebViewConfiguration()
        ImageInsertionHelper.registerImageSchemeHandler(on: config)
        webView = WKWebView(frame: CGRect(origin: .zero, size: paperSize), configuration: config)
        
        let hostView = NSView(frame: CGRect(origin: .zero, size: paperSize))
        hostView.addSubview(webView)
        webView.autoresizingMask = [.width, .height]
        webView.frame = hostView.bounds
        
        hostWindow = NSWindow(
            contentRect: CGRect(origin: .zero, size: paperSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.contentView = hostView
        hostWindow.isReleasedWhenClosed = false
        hostWindow.setFrameOrigin(NSPoint(x: -paperSize.width - 100, y: -paperSize.height - 100))
        hostWindow.orderBack(nil)
        
        super.init()
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: baseURL ?? BundledKaTeX.resourceBaseURL ?? BundledHighlightJS.resourceBaseURL)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            self?.beginPDFRenderIfNeeded()
        }
    }
    
    deinit {
        if Thread.isMainThread {
            hostWindow.orderOut(nil)
        } else {
            DispatchQueue.main.async { [hostWindow] in
                hostWindow.orderOut(nil)
            }
        }
    }
    
    func renderPDF(completion: @escaping (Result<Data, Error>) -> Void) {
        pdfCompletion = completion
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        beginPDFRenderIfNeeded()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(with: error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(with: error)
    }
    
    private func fail(with error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let pdfCompletion = self.pdfCompletion else { return }
            self.pdfCompletion = nil
            self.hostWindow.orderOut(nil)
            pdfCompletion(.failure(error))
        }
    }
    
    private func beginPDFRenderIfNeeded() {
        guard !didStartRender, pdfCompletion != nil else { return }
        didStartRender = true
        
        let prepareForPDF = """
        (async function() {
            if (document.readyState !== 'complete') {
                await new Promise(resolve => window.addEventListener('load', resolve, { once: true }));
            }
            const imgs = Array.from(document.images || []);
            const pending = imgs.filter(i => !i.complete);
            if (pending.length) {
                await Promise.all(pending.map(img => new Promise(resolve => {
                    img.addEventListener('load', resolve, { once: true });
                    img.addEventListener('error', resolve, { once: true });
                })));
            }
            document.querySelectorAll('details').forEach(d => {
                d.open = true;
                d.setAttribute('open', 'open');
                d.classList.add('export-open');
            });
            if (typeof hljs !== 'undefined') {
                document.querySelectorAll('pre code').forEach(block => {
                    if (block.closest('table.hljs-ln')) return;
                    hljs.highlightElement(block);
                    const pre = block.closest('pre');
                    if (pre) pre.classList.add('hljs');
                });
                document.querySelectorAll('table.hljs-ln').forEach(t => t.remove());
            }
            if (typeof typesetExportMath === 'function') {
                typesetExportMath(document.querySelector('.markdown-body') || document.body);
            }
            if (typeof renderExportMermaid === 'function') {
                await renderExportMermaid();
            }
            let lastHeight = 0;
            let stablePasses = 0;
            for (let i = 0; i < 30 && stablePasses < 4; i++) {
                await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
                const h = Math.max(
                    document.body.scrollHeight,
                    document.documentElement.scrollHeight,
                    document.body.offsetHeight
                );
                if (h === lastHeight) stablePasses++;
                else { stablePasses = 0; lastHeight = h; }
            }
            return lastHeight;
        })();
        """
        
        webView.callAsyncJavaScript(prepareForPDF, arguments: [:], in: nil, in: .page) { @MainActor [weak self] (result: Result<Any, Error>) in
            guard let self else { return }
            let contentHeight: CGFloat
            if case .success(let value) = result, let number = value as? NSNumber {
                contentHeight = max(CGFloat(truncating: number), self.paperSize.height)
            } else if case .success(let value) = result, let d = value as? Double {
                contentHeight = max(CGFloat(d), self.paperSize.height)
            } else {
                contentHeight = self.paperSize.height
            }
            self.applyPrintLayout(contentHeight: contentHeight + 48)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.exportPaginatedPDF()
            }
        }
    }
    
    private func applyPrintLayout(contentHeight: CGFloat) {
        let size = CGSize(width: paperSize.width, height: contentHeight)
        var frame = hostWindow.frame
        frame.size = size
        hostWindow.setFrame(frame, display: true)
        if let hostView = hostWindow.contentView {
            hostView.frame = CGRect(origin: .zero, size: size)
            webView.frame = hostView.bounds
        }
        if let scrollView = webView.enclosingScrollView {
            scrollView.documentView?.frame = CGRect(origin: .zero, size: size)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
    
    private func exportPaginatedPDF() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.exportPaginatedPDF() }
            return
        }
        guard pdfCompletion != nil else { return }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blackbeareditor-export-\(UUID().uuidString).pdf")
        savePDFURL = tempURL
        
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        printInfo.paperSize = NSSize(width: paperSize.width, height: paperSize.height)
        printInfo.topMargin = margins
        printInfo.bottomMargin = margins
        printInfo.leftMargin = margins
        printInfo.rightMargin = margins
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobDisposition] = NSPrintInfo.JobDisposition.save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = tempURL
        
        let printOperation = webView.printOperation(with: printInfo)
        printOperation.showsPrintPanel = false
        printOperation.showsProgressPanel = false
        
        // run() падает с EXC_BREAKPOINT для WKWebView — только modal.
        printOperation.runModal(
            for: hostWindow,
            delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }
    
    @objc private func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        // Колбэк печати приходит с фонового потока — UI только на main.
        DispatchQueue.main.async { [weak self] in
            self?.finishPrintExport(success: success)
        }
    }
    
    private func finishPrintExport(success: Bool) {
        hostWindow.orderOut(nil)
        guard let completion = pdfCompletion else { return }
        pdfCompletion = nil
        
        guard success,
              let url = savePDFURL,
              FileManager.default.fileExists(atPath: url.path) else {
            if let url = savePDFURL { try? FileManager.default.removeItem(at: url) }
            savePDFURL = nil
            completion(.failure(ExportError.conversionFailed("PDF export failed.")))
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
            savePDFURL = nil
            completion(.success(data))
        } catch {
            try? FileManager.default.removeItem(at: url)
            savePDFURL = nil
            completion(.failure(error))
        }
    }
}
