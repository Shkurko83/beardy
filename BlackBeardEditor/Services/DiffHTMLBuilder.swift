import Foundation
import Markdown

enum DiffHTMLBuilder {

    static func build(
        chunks: [DiffChunk],
        documentURL: URL?,
        isDark: Bool,
        themeCSS: String,
        codeTheme: String = ThemeService.shared.currentCodeTheme.rawValue
    ) -> DiffRenderResult {
        var body = ""
        var changeCount = 0
        var cursor = 0
        var changeRanges: [Int: (start: Int, weight: Int, isInsertion: Bool)] = [:]

        for chunk in chunks {
            body += emitChunk(
                chunk,
                documentURL: documentURL,
                cursor: &cursor,
                changeCount: &changeCount,
                changeRanges: &changeRanges
            )
        }

        let totalWeight = max(cursor, 1)
        let minFraction: CGFloat = 0.006
        let maxFraction: CGFloat = 0.045

        let segments: [DiffMinimapSegment] = changeRanges
            .sorted { $0.key < $1.key }
            .map { index, range in
                let rawLength = CGFloat(range.weight) / CGFloat(totalWeight)
                let length = min(max(rawLength, minFraction), maxFraction)
                let start = min(
                    CGFloat(range.start) / CGFloat(totalWeight),
                    1.0 - length
                )
                return DiffMinimapSegment(
                    id: index,
                    start: start,
                    length: length,
                    isInsertion: range.isInsertion
                )
            }

        let diffCSS = diffStyles(isDark: isDark)
        let hljsTheme = BundledHighlightJS.relativeThemeCSSPath(
            for: CodeTheme(rawValue: codeTheme) ?? .github
        )
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="\(hljsTheme)">
        <link rel="stylesheet" href="\(BundledKaTeX.relativeCSSPath())">
        <style>
        \(themeCSS)
        \(diffCSS)
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            margin: 0;
            padding: 40px 48px 80px;
            line-height: 1.65;
        }
        #diff-content { max-width: 900px; margin: 0 auto; }
        #diff-content > *:first-child { margin-top: 0; }
        #diff-content blockquote,
        #diff-content .diff-blockquote {
            margin: 0.75em 0;
            padding: 0.35em 0 0.35em 1em;
            border-left: 4px solid var(--md-divider, var(--md-secondary, #8c959f));
            color: var(--md-secondary, #57606a);
            background: transparent;
        }
        #diff-content blockquote p,
        #diff-content .diff-blockquote p {
            margin: 0.35em 0;
        }
        #diff-content blockquote p:first-child,
        #diff-content .diff-blockquote p:first-child { margin-top: 0; }
        #diff-content blockquote p:last-child,
        #diff-content .diff-blockquote p:last-child { margin-bottom: 0; }
        #diff-content ul, #diff-content ol,
        #diff-content .diff-list {
            padding-left: 1.75em;
            margin: 0.5em 0;
        }
        #diff-content li,
        #diff-content .diff-list li {
            margin: 0.25em 0;
            line-height: 1.5;
        }
        #diff-content .diff-nested-list {
            margin: 0.35em 0 0.2em;
            padding-left: 1.5em;
        }
        #diff-content li > .diff-list,
        #diff-content li > ul,
        #diff-content li > ol {
            margin-top: 0.35em;
            margin-bottom: 0.15em;
        }
        #diff-content ul.task-list,
        #diff-content .diff-list.task-list {
            list-style: none;
            padding-left: 0;
        }
        #diff-content li.task-list-item,
        #diff-content .diff-list li.task-list-item {
            list-style: none;
            display: flex;
            align-items: flex-start;
            gap: 0.5em;
        }
        #diff-content .diff-task-checkbox {
            margin-top: 0.2em;
            flex-shrink: 0;
            pointer-events: none;
        }
        img { max-width: 100%; height: auto; display: block; margin: 12px 0; }
        pre { border-radius: 8px; margin: 1em 0; overflow-x: auto; }
        code { font-family: "SF Mono", Menlo, monospace; font-size: 13px; }
        .math-display { margin: 0.75em 0; overflow-x: auto; text-align: center; }
        .math-inline .katex { font-size: 1.05em; }
        .diff-table { width: 100%; border-collapse: collapse; margin: 0.75em 0; }
        .diff-table th, .diff-table td { border: 1px solid var(--md-border, #d0d7de); padding: 6px 10px; vertical-align: top; }
        .diff-table thead { background: rgba(128,128,128,0.12); }
        </style>
        <script src="\(BundledHighlightJS.relativeScriptPath())"></script>
        <script src="\(BundledKaTeX.relativeScriptPath())"></script>
        <script src="\(BundledMermaid.relativeScriptPath())"></script>
        </head>
        <body>
        <div id="diff-content">\(body)</div>
        <script>
        window.__diffScrollRestore = null;

        function captureDiffScrollAnchor() {
            const root = document.getElementById('diff-content');
            if (!root) return null;
            const targetY = window.scrollY + window.innerHeight * 0.33;
            const sections = root.querySelectorAll('[data-diff-ordinal]');
            if (!sections.length) {
                const max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
                return { ordinal: null, ratio: window.scrollY / max };
            }
            let best = null;
            let bestDist = Infinity;
            sections.forEach(function(el) {
                const top = el.offsetTop;
                const dist = Math.abs(top - targetY);
                if (dist < bestDist) {
                    bestDist = dist;
                    const h = Math.max(el.offsetHeight, 1);
                    best = {
                        ordinal: el.getAttribute('data-diff-ordinal'),
                        ratio: Math.max(0, Math.min(1, (targetY - top) / h)),
                        top: top
                    };
                }
            });
            return best;
        }

        function restoreDiffScrollAnchor() {
            const anchor = window.__diffScrollRestore;
            if (!anchor) return false;
            const root = document.getElementById('diff-content');
            if (!root) return false;
            if (anchor.ordinal != null && anchor.ordinal !== '') {
                const candidates = root.querySelectorAll('[data-diff-ordinal="' + anchor.ordinal + '"]');
                let el = candidates[0];
                if (candidates.length > 1 && typeof anchor.top === 'number') {
                    let bestDist = Infinity;
                    candidates.forEach(function(c) {
                        const d = Math.abs(c.offsetTop - anchor.top);
                        if (d < bestDist) {
                            bestDist = d;
                            el = c;
                        }
                    });
                }
                if (el) {
                    const top = el.offsetTop;
                    const h = Math.max(el.offsetHeight, 1);
                    const y = top + anchor.ratio * h - window.innerHeight * 0.33;
                    window.scrollTo(0, Math.max(0, y));
                    return true;
                }
            }
            if (typeof anchor.ratio === 'number') {
                const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                window.scrollTo(0, anchor.ratio * max);
                return true;
            }
            return false;
        }

        function scheduleDiffScrollRestore() {
            restoreDiffScrollAnchor();
            requestAnimationFrame(function() {
                restoreDiffScrollAnchor();
                requestAnimationFrame(restoreDiffScrollAnchor);
            });
            setTimeout(restoreDiffScrollAnchor, 80);
            setTimeout(restoreDiffScrollAnchor, 250);
        }

        function scrollToChangeIndex(index) {
            const root = document.getElementById('diff-content');
            if (!root) return;
            const sel = '[data-change-index="' + index + '"]';
            const el = root.querySelector('.diff-inline-rendered' + sel)
                || root.querySelector('.diff-block-del' + sel)
                || root.querySelector('.diff-block-ins' + sel)
                || root.querySelector('.diff-cell-change' + sel)
                || root.querySelector(sel);
            if (!el) return;
            document.querySelectorAll('.diff-current-focus').forEach(n => n.classList.remove('diff-current-focus'));
            el.classList.add('diff-current-focus');
            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
        (function init() {
            const root = document.getElementById('diff-content');
            if (!root) return;
            if (typeof hljs !== 'undefined') hljs.highlightAll();
            if (typeof katex !== 'undefined') {
                function renderLatex(latex, displayMode) {
                    try {
                        return katex.renderToString(latex, { displayMode: displayMode, throwOnError: false, strict: 'ignore', trust: true });
                    } catch (e) { return null; }
                }
                root.querySelectorAll('.math-display[data-latex]').forEach(function(el) {
                    const latex = el.getAttribute('data-latex') || '';
                    const html = renderLatex(latex, true);
                    if (html) el.innerHTML = html;
                });
                root.querySelectorAll('p, li, h1, h2, h3, h4, h5, h6, td, th').forEach(function(el) {
                    if (el.closest('pre, code') || el.classList.contains('math-display')) return;
                    const t = el.textContent.trim();
                    if (t.startsWith('$$') && t.endsWith('$$') && t.length > 4) {
                        const html = renderLatex(t.slice(2, -2).trim(), true);
                        if (html) el.outerHTML = '<div class="math-display">' + html + '</div>';
                        return;
                    }
                    let inner = el.innerHTML;
                    if (!/\\$/.test(inner)) return;
                    const next = inner.replace(/(^|[^\\$])\\$(?!\\$)((?:\\\\.|[^$\\n\\\\])+?)\\$(?!\\$)/g, function(m, pre, latex) {
                        const out = renderLatex(latex, false);
                        return out ? pre + '<span class="math-inline">' + out + '</span>' : m;
                    });
                    if (next !== inner) el.innerHTML = next;
                });
            }
            if (typeof mermaid !== 'undefined') {
                (async function() {
                    const codes = Array.from(root.querySelectorAll('pre code.language-mermaid, pre code.mermaid'));
                    const nodes = [];
                    codes.forEach(function(code) {
                        const pre = code.closest('pre');
                        if (!pre) return;
                        const div = document.createElement('div');
                        div.className = 'mermaid-diagram';
                        div.textContent = code.textContent || '';
                        pre.replaceWith(div);
                        nodes.push(div);
                    });
                    if (!nodes.length) return;
                    try {
                        mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'default' });
                        await mermaid.run({ nodes: nodes });
                    } catch (e) { console.warn(e); }
                    scheduleDiffScrollRestore();
                })();
            }
            scheduleDiffScrollRestore();
        })();
        </script>
        </body>
        </html>
        """

        return DiffRenderResult(
            html: html,
            changeCount: changeCount,
            minimapSegments: segments
        )
    }

    private static func minimapWeight(for chunk: DiffChunk) -> Int {
        let textLen = max(chunk.text.count, 1)
        switch chunk.kind {
        case .equal:
            return textLen
        case .inserted, .deleted:
            return max(textLen, 12)
        case .blockInserted, .blockDeleted:
            return max(textLen, 48)
        }
    }

    private static func emitChunk(
        _ chunk: DiffChunk,
        documentURL: URL?,
        cursor: inout Int,
        changeCount: inout Int,
        changeRanges: inout [Int: (start: Int, weight: Int, isInsertion: Bool)]
    ) -> String {
        let weight = minimapWeight(for: chunk)
        if let idx = chunk.changeIndex {
            changeCount = max(changeCount, idx)
            let isInsertion = chunk.kind == .inserted || chunk.kind == .blockInserted
            if var existing = changeRanges[idx] {
                existing.weight += weight
                changeRanges[idx] = existing
            } else {
                changeRanges[idx] = (start: cursor, weight: weight, isInsertion: isInsertion)
            }
        }
        let html = wrapSection(chunk, inner: wrapChunk(chunk, documentURL: documentURL))
        cursor += weight
        return html
    }

    private static func wrapSection(_ chunk: DiffChunk, inner: String) -> String {
        guard let ordinal = chunk.blockOrdinal else { return inner }
        return "<div class=\"diff-section\" data-diff-ordinal=\"\(ordinal)\">\(inner)</div>\n"
    }

    private static func wrapChunk(_ chunk: DiffChunk, documentURL: URL?) -> String {
        if let prebuilt = chunk.renderedHTML, !prebuilt.isEmpty {
            return wrapPrebuilt(chunk, html: prebuilt)
        }

        switch chunk.kind {
        case .equal:
            return renderMarkdownBlock(chunk.text, documentURL: documentURL)

        case .inserted:
            return span(className: "diff-ins", changeIndex: chunk.changeIndex, inner: escapeHTML(chunk.text))

        case .deleted:
            return span(className: "diff-del", changeIndex: chunk.changeIndex, inner: escapeHTML(chunk.text))

        case .blockInserted:
            let rendered = renderMarkdownBlock(chunk.text, documentURL: documentURL)
            return blockWrap(className: "diff-block-ins", changeIndex: chunk.changeIndex, inner: rendered)

        case .blockDeleted:
            let rendered = renderMarkdownBlock(chunk.text, documentURL: documentURL)
            return blockWrap(className: "diff-block-del", changeIndex: chunk.changeIndex, inner: rendered)
        }
    }

    private static func wrapPrebuilt(_ chunk: DiffChunk, html: String) -> String {
        let idx = chunk.changeIndex.map { " data-change-index=\"\($0)\"" } ?? ""
        switch chunk.kind {
        case .blockDeleted:
            return "<div class=\"diff-block-del\"\(idx)>\(html)</div>\n"
        case .blockInserted:
            return "<div class=\"diff-block-ins\"\(idx)>\(html)</div>\n"
        case .equal:
            if chunk.changeIndex != nil {
                return "<div class=\"diff-inline-rendered\"\(idx)>\(html)</div>\n"
            }
            return html
        default:
            return "<div class=\"diff-inline-rendered\"\(idx)>\(html)</div>\n"
        }
    }

    private static func renderMarkdownBlock(_ text: String, documentURL: URL?) -> String {
        DiffMarkupRenderer.renderBlock(text, documentURL: documentURL)
    }

    private static func span(className: String, changeIndex: Int?, inner: String) -> String {
        let idx = changeIndex.map { " data-change-index=\"\($0)\"" } ?? ""
        return "<span class=\"\(className)\"\(idx)>\(inner)</span> "
    }

    private static func blockWrap(className: String, changeIndex: Int?, inner: String) -> String {
        let idx = changeIndex.map { " data-change-index=\"\($0)\"" } ?? ""
        return "<div class=\"\(className)\"\(idx)>\(inner)</div>\n"
    }

    private static func escapeHTML(_ text: String) -> String {
        DiffMarkupRenderer.escapeHTML(text)
    }

    static func diffStyles(isDark: Bool) -> String {
        if isDark {
            return """
            .diff-ins { background: #1a3a22; color: #8bc99a; border-radius: 3px; padding: 0 2px; text-decoration: underline; text-decoration-color: #3fb950; }
            .diff-del { background: #3a1a1a; color: #e08080; text-decoration: line-through; border-radius: 3px; padding: 0 2px; }
            .diff-block-ins { background: #172d1e; border-left: 3px solid #3fb950; padding: 12px 16px; margin: 0.75em 0; border-radius: 4px; }
            .diff-block-del { background: #2d1717; border-left: 3px solid #f85149; padding: 12px 16px; margin: 0.75em 0; border-radius: 4px; }
            .diff-block-del * { text-decoration: none !important; }
            .diff-block-ins * { text-decoration: none !important; }
            .diff-inline-text { margin: 0.5em 0; line-height: 1.65; }
            .diff-inline-rendered { margin: 0.5em 0; line-height: 1.65; padding: 4px 2px; background: transparent; border: none; border-radius: 4px; }
            .diff-cell-change { display: inline; }
            .diff-block-del.diff-current-focus, .diff-block-ins.diff-current-focus,
            .diff-inline-rendered.diff-current-focus { outline: 2px solid currentColor; box-shadow: 0 0 0 3px rgba(127,127,127,0.35); }
            .diff-inline-rendered .diff-del, .diff-inline-text .diff-del { background: #3a1a1a; color: #e08080; text-decoration: line-through; border-radius: 3px; padding: 0 2px; }
            .diff-inline-rendered .diff-ins, .diff-inline-text .diff-ins { background: #1a3a22; color: #8bc99a; text-decoration: underline; text-decoration-color: #3fb950; border-radius: 3px; padding: 0 2px; }
            .diff-current-focus { outline: 2px solid currentColor; box-shadow: 0 0 0 3px rgba(127,127,127,0.35); border-radius: 4px; }
            """
        }
        return """
        .diff-ins { background: #d4f4da; border-radius: 3px; padding: 0 2px; text-decoration: underline; text-decoration-color: #2da44e; }
        .diff-del { background: #ffd7d5; text-decoration: line-through; border-radius: 3px; padding: 0 2px; }
        .diff-block-ins { background: #c8efd0; border-left: 3px solid #2da44e; padding: 12px 16px; margin: 0.75em 0; border-radius: 4px; }
        .diff-block-del { background: #fae0de; border-left: 3px solid #cf222e; padding: 12px 16px; margin: 0.75em 0; border-radius: 4px; }
        .diff-block-del * { text-decoration: none !important; }
        .diff-block-ins * { text-decoration: none !important; }
        .diff-inline-text { margin: 0.5em 0; line-height: 1.65; }
        .diff-inline-rendered { margin: 0.5em 0; line-height: 1.65; padding: 4px 2px; background: transparent; border: none; border-radius: 4px; }
        .diff-cell-change { display: inline; }
        .diff-block-del.diff-current-focus, .diff-block-ins.diff-current-focus,
        .diff-inline-rendered.diff-current-focus { outline: 2px solid currentColor; box-shadow: 0 0 0 3px rgba(0,0,0,0.12); }
        .diff-inline-rendered .diff-del, .diff-inline-text .diff-del { background: #ffd7d5; text-decoration: line-through; border-radius: 3px; padding: 0 2px; }
        .diff-inline-rendered .diff-ins, .diff-inline-text .diff-ins { background: #d4f4da; text-decoration: underline; text-decoration-color: #2da44e; border-radius: 3px; padding: 0 2px; }
        .diff-current-focus { outline: 2px solid currentColor; box-shadow: 0 0 0 3px rgba(0,0,0,0.12); border-radius: 4px; }
        """
    }
}
