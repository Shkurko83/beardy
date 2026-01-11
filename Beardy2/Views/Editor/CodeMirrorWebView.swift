
import SwiftUI
import WebKit

struct CodeMirrorWebView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let isDark: Bool
    let viewMode: ViewMode
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        
        let contentController = webView.configuration.userContentController
        contentController.add(context.coordinator, name: "contentChanged")
        contentController.add(context.coordinator, name: "logging")
        contentController.add(context.coordinator, name: "swapPanes") // Новый обработчик
            
        // Перехват console.log
        let loggingScript = WKUserScript(
            source: """
            (function() {
                const originalLog = console.log;
                console.log = function(...args) {
                    originalLog.apply(console, args);
                    window.webkit.messageHandlers.logging.postMessage(args.join(' '));
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(loggingScript)
            
        #if DEBUG
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        
        if let htmlPath = Bundle.main.path(forResource: "codemirror-editor", ofType: "html"),
           let htmlDirectory = Bundle.main.resourcePath {
            let htmlURL = URL(fileURLWithPath: htmlPath)
            let directoryURL = URL(fileURLWithPath: htmlDirectory)
            webView.loadFileURL(htmlURL, allowingReadAccessTo: directoryURL)
        }
        
        context.coordinator.webView = webView
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.pageLoaded else { return }
        
        // Обновление текста
        if !context.coordinator.isUpdatingFromJS && context.coordinator.lastKnownText != text {
            context.coordinator.lastKnownText = text
            let escapedText = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\"", with: "\\\"")
            
            let script = "window.cmEditor?.updateContent(`\(escapedText)`);"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
        
        updateThemeAndMode(webView, context: context)
    }
    
    private func updateThemeAndMode(_ webView: WKWebView, context: Context) {
        guard context.coordinator.pageLoaded else { return }
        
        if context.coordinator.lastTheme != isDark {
            context.coordinator.lastTheme = isDark
            webView.evaluateJavaScript("window.cmEditor?.setTheme(\(isDark));")
        }
        
        if context.coordinator.lastViewMode != viewMode {
            context.coordinator.lastViewMode = viewMode
            let mode = viewMode == .edit ? "edit" : (viewMode == .preview ? "preview" : "split")
            webView.evaluateJavaScript("window.cmEditor?.setViewMode('\(mode)');")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: CodeMirrorWebView
        var webView: WKWebView?
        var isUpdatingFromJS = false
        var lastKnownText = ""
        var lastTheme: Bool?
        var lastViewMode: ViewMode?
        var pageLoaded = false
        
        init(_ parent: CodeMirrorWebView) {
            self.parent = parent
            self.lastKnownText = parent.text
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Логирование для отладки
            webView.evaluateJavaScript("console.log('✅ WebView загружен');") { _, _ in }

            let initialText = parent.text
            let escapedText = initialText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\"", with: "\\\"")
            
            // Инициализация редактора
            let script = """
            console.log('🔧 Инициализация из Swift');
            window.initializeEditor(`\(escapedText)`, \(parent.isDark));
            """
            
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("❌ Ошибка инициализации:", error)
                } else {
                    print("✅ Редактор инициализирован")
                }
            }
            
            // Установка режима
            let mode = parent.viewMode == .edit ? "edit" : (parent.viewMode == .preview ? "preview" : "split")
            webView.evaluateJavaScript("window.cmEditor?.setViewMode('\(mode)');")
            
            // Восстановление состояния swap из UserDefaults
            let isSwapped = UserDefaults.standard.bool(forKey: "editorPanesSwapped")
            webView.evaluateJavaScript("window.cmEditor?.setSwapped(\(isSwapped));")
            
            // Сохраняем состояние
            lastKnownText = initialText
            lastTheme = parent.isDark
            lastViewMode = parent.viewMode
            pageLoaded = true
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            
            if message.name == "logging" {
                print("🌐 JS:", message.body)
                return
            }
            
            if message.name == "contentChanged", let newText = message.body as? String {
                isUpdatingFromJS = true
                lastKnownText = newText
                DispatchQueue.main.async {
                    self.parent.text = newText
                }
                isUpdatingFromJS = false
            }
            
            // Обработка изменения порядка панелей
            if message.name == "swapPanes", let isSwapped = message.body as? Bool {
                UserDefaults.standard.set(isSwapped, forKey: "editorPanesSwapped")
                print("💾 Сохранено состояние swap: \(isSwapped)")
            }
        }
    }
}
//import SwiftUI
//import WebKit
//
//struct CodeMirrorWebView: NSViewRepresentable {
//    @Binding var text: String
//    @Binding var selectedRange: NSRange
//    let isDark: Bool
//    let viewMode: ViewMode
//    
//    func makeNSView(context: Context) -> WKWebView {
//        let config = WKWebViewConfiguration()
//        let webView = WKWebView(frame: .zero, configuration: config)
//        
//        webView.navigationDelegate = context.coordinator
//        webView.setValue(false, forKey: "drawsBackground")
//        
//        let contentController = webView.configuration.userContentController
//        contentController.add(context.coordinator, name: "contentChanged")
//        contentController.add(context.coordinator, name: "logging")
//            
//        // Перехват console.log
//        let loggingScript = WKUserScript(
//            source: """
//            (function() {
//                const originalLog = console.log;
//                console.log = function(...args) {
//                    originalLog.apply(console, args);
//                    window.webkit.messageHandlers.logging.postMessage(args.join(' '));
//                };
//            })();
//            """,
//            injectionTime: .atDocumentStart,
//            forMainFrameOnly: true
//        )
//        contentController.addUserScript(loggingScript)
//            
//        #if DEBUG
//        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
//        #endif
//        
//        if let htmlPath = Bundle.main.path(forResource: "codemirror-editor", ofType: "html"),
//           let htmlDirectory = Bundle.main.resourcePath {
//            let htmlURL = URL(fileURLWithPath: htmlPath)
//            let directoryURL = URL(fileURLWithPath: htmlDirectory)
//            webView.loadFileURL(htmlURL, allowingReadAccessTo: directoryURL)
//        }
//        
//        context.coordinator.webView = webView
//        return webView
//    }
//    
//    func updateNSView(_ webView: WKWebView, context: Context) {
//        guard context.coordinator.pageLoaded else { return }
//        
//        // Обновление текста
//        if !context.coordinator.isUpdatingFromJS && context.coordinator.lastKnownText != text {
//            context.coordinator.lastKnownText = text
//            let escapedText = text
//                .replacingOccurrences(of: "\\", with: "\\\\")
//                .replacingOccurrences(of: "`", with: "\\`")
//                .replacingOccurrences(of: "$", with: "\\$")
//                .replacingOccurrences(of: "\n", with: "\\n")
//                .replacingOccurrences(of: "\r", with: "\\r")
//                .replacingOccurrences(of: "\"", with: "\\\"")
//            
//            let script = "window.cmEditor?.updateContent(`\(escapedText)`);"
//            webView.evaluateJavaScript(script, completionHandler: nil)
//        }
//        
//        updateThemeAndMode(webView, context: context)
//    }
//    
//    private func updateThemeAndMode(_ webView: WKWebView, context: Context) {
//        guard context.coordinator.pageLoaded else { return }
//        
//        if context.coordinator.lastTheme != isDark {
//            context.coordinator.lastTheme = isDark
//            webView.evaluateJavaScript("window.cmEditor?.setTheme(\(isDark));")
//        }
//        
//        if context.coordinator.lastViewMode != viewMode {
//            context.coordinator.lastViewMode = viewMode
//            let mode = viewMode == .edit ? "edit" : (viewMode == .preview ? "preview" : "split")
//            webView.evaluateJavaScript("window.cmEditor?.setViewMode('\(mode)');")
//        }
//    }
//    
//    func makeCoordinator() -> Coordinator {
//        Coordinator(self)
//    }
//    
//    // MARK: - Coordinator
//    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
//        var parent: CodeMirrorWebView
//        var webView: WKWebView?
//        var isUpdatingFromJS = false
//        var lastKnownText = ""
//        var lastTheme: Bool?
//        var lastViewMode: ViewMode?
//        var pageLoaded = false
//        
//        init(_ parent: CodeMirrorWebView) {
//            self.parent = parent
//            self.lastKnownText = parent.text
//        }
//        
//        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
//            // Логирование для отладки
//            webView.evaluateJavaScript("console.log('✅ WebView загружен');") { _, _ in }
//
//            let initialText = parent.text
//            let escapedText = initialText
//                .replacingOccurrences(of: "\\", with: "\\\\")
//                .replacingOccurrences(of: "`", with: "\\`")
//                .replacingOccurrences(of: "$", with: "\\$")
//                .replacingOccurrences(of: "\n", with: "\\n")
//                .replacingOccurrences(of: "\r", with: "\\r")
//                .replacingOccurrences(of: "\"", with: "\\\"")
//            
//            // Инициализация редактора
//            let script = """
//            console.log('🔧 Инициализация из Swift');
//            window.initializeEditor(`\(escapedText)`, \(parent.isDark));
//            """
//            
//            webView.evaluateJavaScript(script) { result, error in
//                if let error = error {
//                    print("❌ Ошибка инициализации:", error)
//                } else {
//                    print("✅ Редактор инициализирован")
//                }
//            }
//            
//            // Установка режима
//            let mode = parent.viewMode == .edit ? "edit" : (parent.viewMode == .preview ? "preview" : "split")
//            webView.evaluateJavaScript("window.cmEditor?.setViewMode('\(mode)');")
//            
//            // Сохраняем состояние
//            lastKnownText = initialText
//            lastTheme = parent.isDark
//            lastViewMode = parent.viewMode
//            pageLoaded = true
//        }
//        
//        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
//            if message.name == "contentChanged", let newText = message.body as? String {
//                isUpdatingFromJS = true
//                lastKnownText = newText
//                DispatchQueue.main.async {
//                    self.parent.text = newText
//                }
//                isUpdatingFromJS = false
//            }
//        }
//    }
//}
