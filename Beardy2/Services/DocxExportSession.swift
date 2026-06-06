//
//  DocxExportSession.swift
//  Beardy2
//
//  Renders Mermaid diagrams and display math via WebKit, then writes DOCX natively.
//

import AppKit
import Foundation
import WebKit

struct DocxRasterAsset {
    enum Kind: String {
        case mermaid
        case mathDisplay
    }

    let kind: Kind
    let pngData: Data
    let widthPx: CGFloat
    let heightPx: CGFloat
}

final class DocxExportSession: NSObject, WKNavigationDelegate {
    private let markdown: String
    private let documentURL: URL?
    private let outputURL: URL
    private let title: String
    private var completion: ((Result<URL, Error>) -> Void)?

    private let webView: WKWebView
    private let hostWindow: NSWindow
    private var didStartCapture = false

    init(
        markdown: String,
        documentURL: URL?,
        outputURL: URL,
        title: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.markdown = markdown
        self.documentURL = documentURL
        self.outputURL = outputURL
        self.title = title
        self.completion = completion

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(ImageSchemeHandler(), forURLScheme: "beardy")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 1200), configuration: config)

        let hostView = NSView(frame: webView.frame)
        hostView.addSubview(webView)
        webView.autoresizingMask = [.width, .height]

        hostWindow = NSWindow(
            contentRect: webView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.contentView = hostView
        hostWindow.isReleasedWhenClosed = false
        hostWindow.setFrameOrigin(NSPoint(x: -2000, y: -2000))
        hostWindow.orderBack(nil)

        super.init()
        webView.navigationDelegate = self

        let html = ExportService.shared.preparedHTMLForDocxExport(
            markdown: markdown,
            documentURL: documentURL
        )
        let baseURL = documentURL?.deletingLastPathComponent()
            ?? BundledKaTeX.resourceBaseURL
            ?? BundledHighlightJS.resourceBaseURL
        webView.loadHTMLString(html, baseURL: baseURL)

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.beginCaptureIfNeeded()
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        beginCaptureIfNeeded()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishWithFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishWithFailure(error)
    }

    private func beginCaptureIfNeeded() {
        guard !didStartCapture, completion != nil else { return }
        didStartCapture = true

        let prepareScript = """
        (async function() {
            async function svgToPng(svg, width, height) {
                const canvas = document.createElement('canvas');
                const scale = 2;
                canvas.width = Math.max(1, Math.ceil(width * scale));
                canvas.height = Math.max(1, Math.ceil(height * scale));
                const ctx = canvas.getContext('2d');
                ctx.scale(scale, scale);
                ctx.fillStyle = '#ffffff';
                ctx.fillRect(0, 0, width, height);
                const clone = svg.cloneNode(true);
                clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
                clone.setAttribute('width', String(width));
                clone.setAttribute('height', String(height));
                const src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(new XMLSerializer().serializeToString(clone));
                await new Promise(function(resolve, reject) {
                    const img = new Image();
                    img.onload = function() { ctx.drawImage(img, 0, 0, width, height); resolve(); };
                    img.onerror = reject;
                    img.src = src;
                });
                return canvas.toDataURL('image/png');
            }
            async function htmlToPng(node, width, height) {
                const canvas = document.createElement('canvas');
                const scale = 2;
                canvas.width = Math.max(1, Math.ceil(width * scale));
                canvas.height = Math.max(1, Math.ceil(height * scale));
                const ctx = canvas.getContext('2d');
                ctx.scale(scale, scale);
                ctx.fillStyle = '#ffffff';
                ctx.fillRect(0, 0, width, height);
                const svgNS = 'http://www.w3.org/2000/svg';
                const svg = document.createElementNS(svgNS, 'svg');
                svg.setAttribute('width', String(width));
                svg.setAttribute('height', String(height));
                const fo = document.createElementNS(svgNS, 'foreignObject');
                fo.setAttribute('width', '100%');
                fo.setAttribute('height', '100%');
                const wrapper = document.createElement('div');
                wrapper.setAttribute('xmlns', 'http://www.w3.org/1999/xhtml');
                wrapper.innerHTML = node.innerHTML;
                fo.appendChild(wrapper);
                svg.appendChild(fo);
                const src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(new XMLSerializer().serializeToString(svg));
                await new Promise(function(resolve, reject) {
                    const img = new Image();
                    img.onload = function() { ctx.drawImage(img, 0, 0, width, height); resolve(); };
                    img.onerror = reject;
                    img.src = src;
                });
                return canvas.toDataURL('image/png');
            }
            if (document.readyState !== 'complete') {
                await new Promise(resolve => window.addEventListener('load', resolve, { once: true }));
            }
            if (typeof typesetExportMath === 'function') {
                typesetExportMath(document.querySelector('.markdown-body') || document.body);
            }
            if (typeof renderExportMermaid === 'function') {
                await renderExportMermaid();
            }
            for (let i = 0; i < 20; i++) {
                await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
            }
            const root = document.querySelector('.markdown-body') || document.body;
            const items = [];
            for (const el of root.querySelectorAll('.mermaid-diagram, .export-mermaid')) {
                const svg = el.querySelector('svg');
                const r = el.getBoundingClientRect();
                if (!svg || r.width < 1 || r.height < 1) continue;
                try {
                    const png = await svgToPng(svg, r.width, r.height);
                    items.push({ kind: 'mermaid', png: png, width: r.width, height: r.height });
                } catch (e) {}
            }
            for (const el of root.querySelectorAll('.math-display')) {
                const r = el.getBoundingClientRect();
                if (r.width < 1 || r.height < 1) continue;
                try {
                    const png = await htmlToPng(el, r.width, r.height);
                    items.push({ kind: 'mathDisplay', png: png, width: r.width, height: r.height });
                } catch (e) {}
            }
            return items;
        })();
        """

        webView.callAsyncJavaScript(prepareScript, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            let assets: [DocxRasterAsset]
            if case .success(let value) = result {
                assets = Self.parseRasterAssets(value)
            } else {
                assets = []
            }
            self.writeDocx(rasterAssets: assets)
        }
    }

    private static func parseRasterAssets(_ value: Any) -> [DocxRasterAsset] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let kindRaw = dict["kind"] as? String,
                  let png = dict["png"] as? String,
                  let width = number(dict["width"]),
                  let height = number(dict["height"]),
                  let data = pngData(from: png),
                  width > 0, height > 1 else { return nil }
            let kind: DocxRasterAsset.Kind = kindRaw == "mathDisplay" ? .mathDisplay : .mermaid
            return DocxRasterAsset(kind: kind, pngData: data, widthPx: width, heightPx: height)
        }
    }

    private static func pngData(from dataURL: String) -> Data? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let encoded = String(dataURL[dataURL.index(after: comma)...])
        return Data(base64Encoded: encoded)
    }

    private func writeDocx(rasterAssets: [DocxRasterAsset]) {
        let markdown = markdown
        let documentURL = documentURL
        let outputURL = outputURL
        let title = title

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try DocxExportWriter.write(
                    markdown: markdown,
                    documentURL: documentURL,
                    title: title,
                    rasterAssets: rasterAssets,
                    to: outputURL
                )
                DispatchQueue.main.async { [weak self] in
                    self?.finishWithSuccess(outputURL)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.finishWithFailure(error)
                }
            }
        }
    }

    private func finishWithSuccess(_ url: URL) {
        guard let completion else { return }
        self.completion = nil
        hostWindow.orderOut(nil)
        completion(.success(url))
    }

    private func finishWithFailure(_ error: Error) {
        guard let completion else { return }
        self.completion = nil
        hostWindow.orderOut(nil)
        completion(.failure(error))
    }

    private static func number(_ value: Any?) -> CGFloat? {
        if let n = value as? NSNumber { return CGFloat(truncating: n) }
        if let d = value as? Double { return CGFloat(d) }
        return nil
    }
}
