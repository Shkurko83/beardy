
import SwiftUI
import WebKit

struct CodeMirrorWebView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let currentDocumentURL: URL?
    let isDark: Bool
    let viewMode: ViewMode
    let previewTheme: ThemeService.EditorTheme
    let codeBlockTheme: ThemeService.CodeTheme
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.setURLSchemeHandler(ImageSchemeHandler(), forURLScheme: "beardy")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        
        let contentController = webView.configuration.userContentController
        contentController.add(context.coordinator, name: "contentChanged")
        contentController.add(context.coordinator, name: "logging")
        contentController.add(context.coordinator, name: "swapPanes")
        
        contentController.add(context.coordinator, name: "openURL")
        contentController.add(context.coordinator, name: "insertImage")
        
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
            // Даём доступ ко всему диску чтобы WebView мог грузить локальные изображения
            let rootURL = URL(fileURLWithPath: "/")
            webView.loadFileURL(htmlURL, allowingReadAccessTo: rootURL)
        }
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleExecJS(_:)),
            name: .editorExecJS,
            object: nil
        )

        
        context.coordinator.webView = webView
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.pageLoaded else { return }
        // Перезагружаем с доступом к папке текущего документа
        if let docURL = context.coordinator.parent.currentDocumentURL,
           context.coordinator.lastDocumentURL != docURL {
            context.coordinator.lastDocumentURL = docURL
            let dirURL = docURL.deletingLastPathComponent()
            if let htmlPath = Bundle.main.path(forResource: "codemirror-editor", ofType: "html") {
                webView.loadFileURL(URL(fileURLWithPath: htmlPath), allowingReadAccessTo: dirURL)
                return
            }
        }
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
            
        if context.coordinator.lastPreviewTheme != previewTheme {
            context.coordinator.lastPreviewTheme = previewTheme
            
            // Генерируем CSS для темы
            let themeCSS = ThemeService.shared.generateCSS(for: previewTheme)
            let script = """
            window.cmEditor?.setPreviewTheme('\(previewTheme.rawValue)', `\(themeCSS)`);
            """
            webView.evaluateJavaScript(script)
        }

        if context.coordinator.lastCodeBlockTheme != codeBlockTheme {
            context.coordinator.lastCodeBlockTheme = codeBlockTheme
            webView.evaluateJavaScript("window.cmEditor?.setCodeBlockTheme('\(codeBlockTheme.rawValue)', '\(codeBlockTheme.cdnURL)');")
        }
    }
    
    private func updateThemeAndMode(_ webView: WKWebView, context: Context) {
        guard context.coordinator.pageLoaded else { return }
        
        if context.coordinator.lastTheme != isDark {
            context.coordinator.lastTheme = isDark
            webView.evaluateJavaScript("window.cmEditor?.setTheme(\(isDark));")
        }
        
        if context.coordinator.lastViewMode != viewMode {
            context.coordinator.lastViewMode = viewMode
            let mode: String
            switch viewMode {
            case .edit:
                mode = "edit"
            case .live:
                mode = "live"
            case .preview:
                mode = "preview"
            case .split:
                mode = "split"
            }
            print("🔥 Initial WebView mode =", mode)
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
        var lastPreviewTheme: ThemeService.EditorTheme
        var lastCodeBlockTheme: ThemeService.CodeTheme
        var lastDocumentURL: URL?
        
        init(_ parent: CodeMirrorWebView) {
            self.parent = parent
            self.lastKnownText = parent.text
            self.lastPreviewTheme = parent.previewTheme
            self.lastCodeBlockTheme = parent.codeBlockTheme
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
            let mode: String
            switch parent.viewMode {
            case .edit:
                mode = "edit"
            case .live:
                mode = "live"
            case .preview:
                mode = "preview"
            case .split:
                mode = "split"
            }
            print("🔥 Updating WebView mode =", mode)
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("❌ Ошибка инициализации:", error)
                } else {
                    print("✅ Редактор инициализирован")

                    let mode: String
                    switch self.parent.viewMode {
                    case .edit: mode = "edit"
                    case .live: mode = "live"
                    case .preview: mode = "preview"
                    case .split: mode = "split"
                    }

                    webView.evaluateJavaScript("window.cmEditor?.setViewMode('\(mode)');")
                }
            }
            
            // Восстановление swap из UserDefaults
            let isSwapped = UserDefaults.standard.bool(forKey: "editorPanesSwapped")
            webView.evaluateJavaScript("window.cmEditor?.setSwapped(\(isSwapped));")
            
            // Применение тем при загрузке
            let themeCSS = ThemeService.shared.generateCSS(for: parent.previewTheme)
            let themeScript = """
            window.cmEditor?.setPreviewTheme('\(parent.previewTheme.rawValue)', `\(themeCSS)`);
            window.cmEditor?.setCodeBlockTheme('\(parent.codeBlockTheme.rawValue)', '\(parent.codeBlockTheme.cdnURL)');
            """
            webView.evaluateJavaScript(themeScript)
            
            // Сохраняем состояние
            lastKnownText = initialText
            lastTheme = parent.isDark
            lastViewMode = parent.viewMode
            lastPreviewTheme = parent.previewTheme
            lastCodeBlockTheme = parent.codeBlockTheme
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
            
            if message.name == "openURL", let urlString = message.body as? String,
               let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            
            if message.name == "insertImage", let params = message.body as? [String: String] {
                let alt = params["alt"] ?? "image"
                let dataURL = params["dataURL"] ?? ""
                let style = params["style"] ?? ""
                
                let markdown: String
                if style.isEmpty {
                    markdown = "![\(alt)](\(dataURL))"
                } else {
                    markdown = "<img src=\"\(dataURL)\" alt=\"\(alt)\" style=\"\(style)\">"
                }
                
                DispatchQueue.main.async {
                    let escaped = markdown
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "`", with: "\\`")
                    let js = "window.cmEditor?.insertText(`\n\n\(escaped)\n\n`);"
                    self.webView?.evaluateJavaScript(js)
                }
            }

        }
        
        func executeFormatting(_ js: String) {
            guard pageLoaded else { return }
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
        @objc func handleExecJS(_ notification: Notification) {
            guard let js = notification.object as? String, pageLoaded else { return }
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
