//
//  CodeMirrorBridge.swift
//  Beardy2
//
//  Created by Butt Simpson on 07.01.2026.
//

import SwiftUI
import WebKit

struct CodeMirrorBridge: NSViewRepresentable {
    @Binding var text: String
    @Binding var viewMode: ViewMode // Твой enum: .edit, .split, .preview
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Разрешаем JS общаться со Swift
        config.userContentController.add(context.coordinator, name: "textChanged")
        
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        
        // Загружаем наш HTML
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Переключаем режимы отображения (Edit/Split/Preview)
        let mode = viewMode == .edit ? "edit" : (viewMode == .preview ? "preview" : "split")
        webView.evaluateJavaScript("setMode('\(mode)')")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: CodeMirrorBridge
        
        init(_ parent: CodeMirrorBridge) { self.parent = parent }

        // Когда страница загрузилась, кидаем в нее текст
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Экранируем спецсимволы, чтобы JS не упал
            let escapedText = parent.text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")

            let jsCall = "initEditor('\(escapedText)')"
            webView.evaluateJavaScript(jsCall) { result, error in
                if let error = error {
                    print("Ошибка инициализации JS: \(error)")
                }
            }
        }
        // Слушаем сообщения из JS
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "textChanged", let newText = message.body as? String {
                self.parent.text = newText
            }
        }
    }
}
