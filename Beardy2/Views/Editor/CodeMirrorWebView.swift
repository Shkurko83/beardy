
import SwiftUI
import WebKit

struct CodeMirrorWebView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let currentDocumentURL: URL?
    let isDark: Bool
    let viewMode: ViewMode
    let editorTheme: EditorThemeIdentity
    let codeBlockTheme: CodeTheme
    let appearanceToken: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let preferences = config.preferences
        // Only use keys that exist on WKPreferences — invalid KVC keys crash the app.
        if preferences.responds(to: Selector(("setAutomaticQuoteSubstitutionEnabled:"))) {
            preferences.setValue(false, forKey: "automaticQuoteSubstitutionEnabled")
        }
        if preferences.responds(to: Selector(("setAutomaticDashSubstitutionEnabled:"))) {
            preferences.setValue(false, forKey: "automaticDashSubstitutionEnabled")
        }
        preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
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
        contentController.add(context.coordinator, name: "processImageFile")
        contentController.add(context.coordinator, name: "outlineHeadings")
        contentController.add(context.coordinator, name: "editorUndoRedo")

        #if DEBUG
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        if let htmlPath = Bundle.main.path(forResource: "codemirror-editor", ofType: "html"),
           let resourceURL = Bundle.main.resourceURL {
            let htmlURL = URL(fileURLWithPath: htmlPath)
            webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceURL)
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleExecJS(_:)),
            name: .editorExecJS,
            object: nil
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleThemeDidChange(_:)),
            name: .themeDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleCodeThemeDidChange(_:)),
            name: .codeThemeDidChange,
            object: nil
        )

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.pageLoaded else { return }

        if let docURL = context.coordinator.parent.currentDocumentURL {
            context.coordinator.lastDocumentURL = docURL
        }

        if !context.coordinator.isUpdatingFromJS && context.coordinator.lastKnownText != text {
            context.coordinator.lastKnownText = text
            let escapedText = escapeForJS(text)
            webView.evaluateJavaScript("window.cmEditor?.updateContent(`\(escapedText)`);", completionHandler: nil)
        }

        updateThemeAndMode(webView, context: context)
        syncDocumentPath(webView, coordinator: context.coordinator)
    }

    private func syncDocumentPath(_ webView: WKWebView, coordinator: Coordinator) {
        let docPath = coordinator.parent.currentDocumentURL?
            .deletingLastPathComponent()
            .path ?? ""
        guard coordinator.lastDocumentBasePath != docPath else { return }
        coordinator.lastDocumentBasePath = docPath
        let escaped = escapeForJS(docPath)
        webView.evaluateJavaScript("window.cmEditor?.setDocumentPath(`\(escaped)`);", completionHandler: nil)
    }

    private func updateThemeAndMode(_ webView: WKWebView, context: Context) {
        guard context.coordinator.pageLoaded else { return }

        let token = appearanceToken
        if context.coordinator.lastAppearanceToken != token {
            context.coordinator.lastAppearanceToken = token
            applyAppearance(to: webView, coordinator: context.coordinator)
        }

        if context.coordinator.lastViewMode != viewMode {
            context.coordinator.lastViewMode = viewMode
            let mode = jsViewModeName(viewMode)
            webView.evaluateJavaScript("window.cmEditor?.setViewMode('\(mode)');", completionHandler: nil)
        }
    }

    func applyAppearance(to webView: WKWebView, coordinator: Coordinator) {
        let themeCSS = ThemeService.shared.generateCSS(for: editorTheme)
        let escapedCSS = escapeForJS(themeCSS)
        let themeId = escapeForJS(editorTheme.id)

        let showLineNumbers = UserDefaults.standard.bool(forKey: AppConstants.Keys.showCodeLineNumbers)
        let focusActive = UserDefaults.standard.bool(forKey: AppConstants.Keys.focusMode)
        let viewRaw = UserDefaults.standard.string(forKey: "selectedViewMode") ?? ViewMode.edit.rawValue
        let readingChrome = focusActive || viewRaw == ViewMode.preview.rawValue
        let focusDim = UserDefaults.standard.bool(forKey: AppConstants.Keys.focusDimInactiveLines)
        let focusHide = readingChrome
        let theme = ThemeService.shared
        let escapedURL = escapeForJS(codeBlockTheme.cdnURL)
        let escapedName = escapeForJS(codeBlockTheme.rawValue)
        let escapedBg = escapeForJS(theme.codeBlockBackgroundHex)
        let escapedBorder = escapeForJS(theme.codeBlockBorderHex)

        let script = """
        (function() {
            if (!window.cmEditor?.applyAppearance) return;
            window.cmEditor.applyAppearance({
                isDark: \(isDark),
                themeId: `\(themeId)`,
                themeCSS: `\(escapedCSS)`,
                codeThemeURL: `\(escapedURL)`,
                codeThemeName: `\(escapedName)`,
                codeBlockBg: `\(escapedBg)`,
                codeBlockBorder: `\(escapedBorder)`,
                showLineNumbers: \(showLineNumbers),
                focusActive: \(readingChrome),
                focusDimLines: \(focusDim),
                focusHideToolbar: \(focusHide)
            });
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)

        coordinator.lastViewMode = viewMode
        coordinator.lastAppearanceToken = appearanceToken
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func jsViewModeName(_ mode: ViewMode) -> String {
        switch mode {
        case .edit: return "edit"
        case .live: return "live"
        case .preview: return "preview"
        case .split: return "split"
        }
    }

    private func escapeForJS(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: CodeMirrorWebView
        var webView: WKWebView?
        var isUpdatingFromJS = false
        var lastKnownText = ""
        var lastViewMode: ViewMode?
        var pageLoaded = false
        var lastAppearanceToken: String?
        var lastDocumentURL: URL?
        var lastDocumentBasePath: String?

        init(_ parent: CodeMirrorWebView) {
            self.parent = parent
            self.lastKnownText = parent.text
            self.lastAppearanceToken = parent.appearanceToken
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let escapedText = parent.escapeForJS(parent.text)
            let initScript = "window.initializeEditor(`\(escapedText)`, \(parent.isDark));"
            let viewMode = parent.jsViewModeName(parent.viewMode)

            webView.evaluateJavaScript(initScript) { _, error in
                if error != nil { return }

                webView.evaluateJavaScript("window.cmEditor?.setViewMode('\(viewMode)');")

                let isSwapped = UserDefaults.standard.bool(forKey: "editorPanesSwapped")
                webView.evaluateJavaScript("window.cmEditor?.setSwapped(\(isSwapped));")

                let syncScroll = UserDefaults.standard.bool(forKey: AppConstants.Keys.previewSyncScroll)
                webView.evaluateJavaScript("window.cmEditor?.setSyncScroll(\(syncScroll));")

                self.pageLoaded = true
                self.lastKnownText = self.parent.text
                self.lastAppearanceToken = self.parent.appearanceToken
                self.parent.applyAppearance(to: webView, coordinator: self)
                self.parent.syncDocumentPath(webView, coordinator: self)
                webView.evaluateJavaScript("window.cmEditor?.publishOutlineHeadings?.();")
            }
        }

        @objc func handleThemeDidChange(_ notification: Notification) {
            guard pageLoaded else { return }
            EditorAppearanceSync.pushToEditor()
            lastAppearanceToken = parent.appearanceToken
        }

        @objc func handleCodeThemeDidChange(_ notification: Notification) {
            guard pageLoaded else { return }
            EditorAppearanceSync.pushToEditor()
            lastAppearanceToken = parent.appearanceToken
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "logging" { return }

            if message.name == "contentChanged", let newText = message.body as? String {
                isUpdatingFromJS = true
                lastKnownText = newText
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.parent.text = newText
                    self.isUpdatingFromJS = false
                }
            }

            if message.name == "swapPanes", let isSwapped = message.body as? Bool {
                UserDefaults.standard.set(isSwapped, forKey: "editorPanesSwapped")
            }

            if message.name == "openURL", let urlString = message.body as? String {
                guard !urlString.hasPrefix("#"),
                      let url = URL(string: urlString),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" || scheme == "mailto" else { return }
                NSWorkspace.shared.open(url)
            }

            if message.name == "processImageFile", let body = message.body as? [String: Any],
               let base64 = body["base64"] as? String,
               let filename = body["filename"] as? String,
               let data = Data(base64Encoded: base64) {
                NotificationCenter.default.post(
                    name: .processImageFile,
                    object: nil,
                    userInfo: ["data": data, "filename": filename]
                )
            }

            if message.name == "editorUndoRedo", let body = message.body as? [String: Any],
               let action = body["action"] as? String {
                let snapshot = body["snapshot"] as? String
                DispatchQueue.main.async {
                    if action == "undo" {
                        DocumentManager.shared?.undo(editorSnapshot: snapshot)
                    } else if action == "redo" {
                        DocumentManager.shared?.redo(editorSnapshot: snapshot)
                    }
                }
            }

            if message.name == "outlineHeadings" {
                guard let data = try? JSONSerialization.data(withJSONObject: message.body),
                      let decoded = try? JSONDecoder().decode([JSOutlineHeading].self, from: data) else { return }
                let items = decoded.map {
                    HeadingItem(level: $0.level, title: $0.title, lineNumber: $0.lineNumber)
                }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .outlineHeadingsDidUpdate,
                        object: items
                    )
                }
            }
        }

        @objc func handleExecJS(_ notification: Notification) {
            guard let js = notification.object as? String, pageLoaded else { return }
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

private struct JSOutlineHeading: Decodable {
    let lineNumber: Int
    let level: Int
    let title: String
}
