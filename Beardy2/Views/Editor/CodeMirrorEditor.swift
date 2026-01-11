//
//  CodeMirrorEditor.swift
//  Beardy2
//
//  Created by Butt Simpson on 07.01.2026.
//

import SwiftUI
import WebKit

struct CodeMirrorEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let isDark: Bool
    let onChange: (String) -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "textDidChange")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        
        context.coordinator.webView = webView
        loadEditor(in: webView, context: context)
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Обновляем текст только если он изменился извне (например, из preview)
        if context.coordinator.lastExternalText != text {
            context.coordinator.lastExternalText = text
            context.coordinator.isUpdatingFromSwift = true
            
            let escapedText = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            
            let js = """
            if (window.editorView) {
                const currentText = window.editorView.state.doc.toString();
                if (currentText !== `\(escapedText)`) {
                    window.editorView.dispatch({
                        changes: {
                            from: 0,
                            to: window.editorView.state.doc.length,
                            insert: `\(escapedText)`
                        }
                    });
                }
            }
            """
            webView.evaluateJavaScript(js) { _, _ in
                context.coordinator.isUpdatingFromSwift = false
            }
        }
        
        // Обновляем тему
        if context.coordinator.lastIsDark != isDark {
            context.coordinator.lastIsDark = isDark
            updateTheme(in: webView, isDark: isDark)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func loadEditor(in webView: WKWebView, context: Context) {
        guard let bundlePath = Bundle.main.path(forResource: "editor.bundle", ofType: "js"),
              let jsCode = try? String(contentsOfFile: bundlePath) else {
            print("❌ Не удалось загрузить editor.bundle.js")
            return
        }
        
        let escapedInitialText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { 
                    height: 100%; 
                    overflow: hidden;
                    font-family: -apple-system, BlinkMacSystemFont, "SF Mono", Monaco, monospace;
                }
                #editor { 
                    height: 100vh; 
                    width: 100%;
                }
                .cm-editor {
                    height: 100%;
                }
                .cm-scroller {
                    overflow: auto;
                    padding: 40px 60px;
                }
                /* Стили для скрытия маркдаун-символов */
                .cm-markdown-hidden {
                    display: none;
                }
                /* Стили для заголовков */
                .cm-heading-1 { font-size: 2em; font-weight: bold; }
                .cm-heading-2 { font-size: 1.5em; font-weight: bold; }
                .cm-heading-3 { font-size: 1.25em; font-weight: bold; }
                .cm-heading-4 { font-size: 1.1em; font-weight: bold; }
                .cm-heading-5 { font-size: 1em; font-weight: bold; }
                .cm-heading-6 { font-size: 0.9em; font-weight: bold; }
                /* Стили для форматирования */
                .cm-strong { font-weight: bold; }
                .cm-emphasis { font-style: italic; }
                .cm-strikethrough { text-decoration: line-through; }
            </style>
        </head>
        <body>
            <div id="editor"></div>
            <script>\(jsCode)</script>
            <script>
                const initialText = `\(escapedInitialText)`;
                const isDarkTheme = \(isDark ? "true" : "false");
                
                // Эту функцию мы определим в editor.bundle.js
                window.editorView = window.initCodeMirror({
                    parent: document.getElementById('editor'),
                    initialText: initialText,
                    isDark: isDarkTheme,
                    onChange: (text) => {
                        window.webkit.messageHandlers.textDidChange.postMessage(text);
                    }
                });
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    private func updateTheme(in webView: WKWebView, isDark: Bool) {
        let js = """
        if (window.updateTheme) {
            window.updateTheme(\(isDark));
        }
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: CodeMirrorEditor
        weak var webView: WKWebView?
        var lastExternalText: String = ""
        var lastIsDark: Bool = false
        var isUpdatingFromSwift: Bool = false
        
        init(_ parent: CodeMirrorEditor) {
            self.parent = parent
            self.lastExternalText = parent.text
            self.lastIsDark = parent.isDark
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "textDidChange",
                  let text = message.body as? String,
                  !isUpdatingFromSwift else { return }
            
            DispatchQueue.main.async {
                self.parent.text = text
                self.lastExternalText = text
                self.parent.onChange(text)
            }
        }
        
    }
}
