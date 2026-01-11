//
//  ProseMirrorWebView.swift
//  Beardy2
//
//  Created by Butt Simpson on 09.01.2026.
//

import SwiftUI
import WebKit

struct ProseMirrorWebView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let isDark: Bool
    let viewMode: ViewMode
    
    func makeNSView(context: Context) -> WKWebView {
        print("🔧 makeNSView вызван")
        
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        
        print("🔧 WKWebView создан, frame: \(webView.frame)")
        
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        
        // Добавляем обработчик JS логов
        let logScript = WKUserScript(
            source: """
            console.log = function(message) {
                window.webkit.messageHandlers.jsLog.postMessage(String(message));
            };
            console.error = function(message) {
                window.webkit.messageHandlers.jsLog.postMessage('ERROR: ' + String(message));
            };
            console.warn = function(message) {
                window.webkit.messageHandlers.jsLog.postMessage('WARN: ' + String(message));
            };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        
        let contentController = webView.configuration.userContentController
        contentController.addUserScript(logScript)
        contentController.add(context.coordinator, name: "jsLog")
        contentController.add(context.coordinator, name: "contentChanged")
        
        #if DEBUG
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        
        // Проверяем путь к HTML
        if let htmlPath = Bundle.main.path(forResource: "prosemirror-editor", ofType: "html") {
            print("✅ HTML файл найден: \(htmlPath)")
            
            if let htmlDirectory = Bundle.main.resourcePath {
                let htmlURL = URL(fileURLWithPath: htmlPath)
                let directoryURL = URL(fileURLWithPath: htmlDirectory)
                
                print("✅ Загружаем HTML из: \(htmlURL)")
                print("✅ Разрешаем доступ к: \(directoryURL)")
                
                webView.loadFileURL(htmlURL, allowingReadAccessTo: directoryURL)
            }
        } else {
            print("❌ HTML файл НЕ НАЙДЕН!")
            print("❌ Искали: prosemirror-editor.html в Bundle.main")
            
            // Выводим все HTML файлы в bundle
            if let resourcePath = Bundle.main.resourcePath {
                do {
                    let files = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                    print("📁 Файлы в bundle:")
                    files.filter { $0.hasSuffix(".html") }.forEach { print("  - \($0)") }
                } catch {
                    print("❌ Не удалось прочитать содержимое bundle: \(error)")
                }
            }
        }
        
        context.coordinator.webView = webView
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.pageLoaded else {
            print("⏳ updateNSView: страница еще не загружена")
            return
        }
        
        if !context.coordinator.isUpdatingFromJS && context.coordinator.lastKnownText != text {
            print("📝 Обновляем контент из Swift")
            context.coordinator.lastKnownText = text
            let escapedText = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "\n", with: "\\n")
            
            webView.evaluateJavaScript("window.pmEditor?.updateContent(`\(escapedText)`);") { result, error in
                if let error = error {
                    print("❌ Ошибка updateContent: \(error)")
                } else {
                    print("✅ updateContent выполнен")
                }
            }
        }
        
        if context.coordinator.lastTheme != isDark {
            context.coordinator.lastTheme = isDark
            webView.evaluateJavaScript("window.pmEditor?.setTheme(\(isDark));")
        }
        
        if context.coordinator.lastViewMode != viewMode {
            context.coordinator.lastViewMode = viewMode
            let mode = viewMode == .edit ? "edit" : (viewMode == .preview ? "preview" : "split")
            webView.evaluateJavaScript("window.pmEditor?.setViewMode('\(mode)');")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: ProseMirrorWebView
        var webView: WKWebView?
        var isUpdatingFromJS = false
        var lastKnownText = ""
        var lastTheme: Bool?
        var lastViewMode: ViewMode?
        var pageLoaded = false
        
        init(_ parent: ProseMirrorWebView) {
            self.parent = parent
            self.lastKnownText = parent.text
            print("🎯 Coordinator инициализирован")
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("✅✅✅ WebView didFinish - страница загружена!")
            pageLoaded = true
            
            let initialText = parent.text
            print("📄 Начальный текст длиной: \(initialText.count) символов")
            
            let escapedText = initialText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            
            let script = "window.initializeEditor(`\(escapedText)`, \(parent.isDark));"
            print("🚀 Выполняем инициализацию...")
            
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("❌❌❌ Ошибка инициализации: \(error)")
                    print("❌ Описание: \(error.localizedDescription)")
                } else {
                    print("✅✅✅ Инициализация успешна!")
                }
            }
            
            // Проверяем, что функция существует
            webView.evaluateJavaScript("typeof window.initializeEditor") { result, error in
                print("🔍 Тип window.initializeEditor: \(result ?? "undefined")")
            }
            
            lastKnownText = initialText
            lastTheme = parent.isDark
            lastViewMode = parent.viewMode
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ WebView didFail: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ WebView didFailProvisionalNavigation: \(error.localizedDescription)")
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "jsLog" {
                print("🌐 JS: \(message.body)")
            } else if message.name == "contentChanged", let newText = message.body as? String {
                print("📝 Получен новый текст из JS, длина: \(newText.count)")
                isUpdatingFromJS = true
                lastKnownText = newText
                DispatchQueue.main.async {
                    self.parent.text = newText
                }
                isUpdatingFromJS = false
            }
        }
    }
}
