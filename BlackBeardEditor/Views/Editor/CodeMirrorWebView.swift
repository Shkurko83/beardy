
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
        ImageInsertionHelper.registerImageSchemeHandler(on: config)

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
        contentController.add(context.coordinator, name: "editorContentFlush")
        contentController.add(context.coordinator, name: "documentContentLoaded")
        contentController.add(context.coordinator, name: "spellCheckRequest")

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

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleFindUpdate(_:)),
            name: .editorFindDidUpdate,
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
            pushContentToEditor(text, webView: webView, coordinator: context.coordinator)
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
        case .experimental: return "experimental"
        case .diff: return "preview"
        }
    }

    private static let inlineEditorContentLimit = 350_000
    private static let contentImportChunkSize = 900_000

    fileprivate func pushContentToEditor(
        _ text: String,
        webView: WKWebView,
        coordinator: Coordinator,
        completion: (() -> Void)? = nil
    ) {
        coordinator.beginDocumentLoad(expectedCharacterCount: text.count)
        coordinator.lastKnownText = text

        if text.count <= Self.inlineEditorContentLimit {
            let escapedText = escapeForJS(text)
            webView.evaluateJavaScript("window.cmEditor?.updateContent(`\(escapedText)`);") { _, _ in
                completion?()
            }
            return
        }

        guard let data = text.data(using: .utf8) else {
            coordinator.endDocumentLoad()
            completion?()
            return
        }

        let encoded = data.base64EncodedString()
        var chunks: [String] = []
        var start = encoded.startIndex
        while start < encoded.endIndex {
            let end = encoded.index(start, offsetBy: Self.contentImportChunkSize, limitedBy: encoded.endIndex) ?? encoded.endIndex
            chunks.append(String(encoded[start..<end]))
            start = end
        }

        webView.evaluateJavaScript("window.cmEditor?.beginContentImport(\(chunks.count));") { _, _ in
            self.appendContentImportChunks(chunks, startingAt: 0, webView: webView) {
                webView.evaluateJavaScript("window.cmEditor?.finishContentImport();") { _, _ in
                    completion?()
                }
            }
        }
    }

    private func appendContentImportChunks(
        _ chunks: [String],
        startingAt index: Int,
        webView: WKWebView,
        completion: @escaping () -> Void
    ) {
        guard index < chunks.count else {
            completion()
            return
        }

        let escaped = escapeForJS(chunks[index])
        let script = "window.cmEditor?.appendContentImportChunk(\(index), `\(escaped)`);"
        webView.evaluateJavaScript(script) { _, _ in
            self.appendContentImportChunks(chunks, startingAt: index + 1, webView: webView, completion: completion)
        }
    }

    private func finishEditorSetup(webView: WKWebView, viewMode: String, coordinator: Coordinator) {
        webView.evaluateJavaScript("window.cmEditor?.setViewMode('\(viewMode)');")

        let isSwapped = UserDefaults.standard.bool(forKey: "editorPanesSwapped")
        webView.evaluateJavaScript("window.cmEditor?.setSwapped(\(isSwapped));")

        let syncScroll = AppConstants.isPreviewSyncScrollEnabled
        webView.evaluateJavaScript("window.cmEditor?.setSyncScroll(\(syncScroll));")
        EditorSettingsSync.pushToEditor()
        TypingSettingsSync.pushToEditor()

        coordinator.pageLoaded = true
        coordinator.flushPendingExecScripts(on: webView)
        coordinator.lastKnownText = text
        coordinator.lastAppearanceToken = appearanceToken
        applyAppearance(to: webView, coordinator: coordinator)
        syncDocumentPath(webView, coordinator: coordinator)
        webView.evaluateJavaScript("window.cmEditor?.publishOutlineHeadings?.();")
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
        private var pendingExecScripts: [String] = []
        private var spellCheckWorkItem: DispatchWorkItem?
        private var documentLoadExpectedCount = 0
        private var documentLoadStartedAt: Date?

        init(_ parent: CodeMirrorWebView) {
            self.parent = parent
            self.lastKnownText = parent.text
            self.lastAppearanceToken = parent.appearanceToken
        }

        func beginDocumentLoad(expectedCharacterCount: Int) {
            documentLoadExpectedCount = max(0, expectedCharacterCount)
            documentLoadStartedAt = Date()
        }

        func endDocumentLoad() {
            documentLoadExpectedCount = 0
            documentLoadStartedAt = nil
        }

        func shouldIgnoreContentChange(_ newText: String) -> Bool {
            guard documentLoadExpectedCount > 0 else { return false }
            if newText.count >= max(256, documentLoadExpectedCount / 2) {
                endDocumentLoad()
                return false
            }
            if let started = documentLoadStartedAt, Date().timeIntervalSince(started) < 60 {
                return true
            }
            endDocumentLoad()
            return false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let viewMode = parent.jsViewModeName(parent.viewMode)
            let useImport = parent.text.count > CodeMirrorWebView.inlineEditorContentLimit

            let completeSetup = {
                self.parent.finishEditorSetup(webView: webView, viewMode: viewMode, coordinator: self)
            }

            if useImport {
                let initScript = "window.initializeEditor('', \(parent.isDark), null);"
                webView.evaluateJavaScript(initScript) { _, error in
                    if error != nil { return }
                    self.parent.pushContentToEditor(self.parent.text, webView: webView, coordinator: self) {
                        completeSetup()
                    }
                }
                return
            }

            let escapedText = parent.escapeForJS(parent.text)
            let initScript = "window.initializeEditor(`\(escapedText)`, \(parent.isDark), '\(viewMode)');"
            webView.evaluateJavaScript(initScript) { _, error in
                if error != nil { return }
                completeSetup()
            }
        }

        fileprivate func flushPendingExecScripts(on webView: WKWebView) {
            let scripts = pendingExecScripts
            pendingExecScripts.removeAll()
            for script in scripts {
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
        }

        @objc func handleThemeDidChange(_ notification: Notification) {
            guard pageLoaded else { return }
            lastAppearanceToken = parent.appearanceToken
        }

        @objc func handleCodeThemeDidChange(_ notification: Notification) {
            guard pageLoaded else { return }
            lastAppearanceToken = parent.appearanceToken
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "logging" { return }

            if message.name == "editorContentFlush", let content = message.body as? String {
                DispatchQueue.main.async {
                    DocumentManager.shared?.deliverFlushedEditorContent(content)
                }
            }

            if message.name == "contentChanged", let newText = message.body as? String {
                if shouldIgnoreContentChange(newText) { return }
                isUpdatingFromJS = true
                lastKnownText = newText
                scheduleSpellCheck(for: newText)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.parent.text = newText
                    self.isUpdatingFromJS = false
                }
            }

            if message.name == "documentContentLoaded", let content = message.body as? String {
                endDocumentLoad()
                isUpdatingFromJS = true
                lastKnownText = content
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.parent.text = content
                    DocumentManager.shared?.refreshStatisticsForCurrentTab()
                    self.isUpdatingFromJS = false
                }
            }

            if message.name == "spellCheckRequest", let text = message.body as? String {
                scheduleSpellCheck(for: text)
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
            guard let js = notification.object as? String else { return }
            guard pageLoaded, let webView else {
                pendingExecScripts.append(js)
                return
            }
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        @objc func handleFindUpdate(_ notification: Notification) {
            guard pageLoaded, let webView else { return }
            guard let userInfo = notification.userInfo else { return }

            if let active = userInfo["active"] as? Bool, !active {
                webView.evaluateJavaScript("window.cmEditor?.clearFindState?.();", completionHandler: nil)
                return
            }

            guard let query = userInfo["query"] as? String,
                  let ranges = userInfo["ranges"] as? [[String: Any]],
                  let currentIndex = userInfo["currentIndex"] as? Int else { return }

            let payload: [String: Any] = [
                "active": true,
                "query": query,
                "ranges": ranges.map { item in
                    [
                        "location": item["location"] ?? 0,
                        "length": item["length"] ?? 0
                    ]
                },
                "currentIndex": currentIndex,
                "caseSensitive": userInfo["caseSensitive"] as? Bool ?? false
            ]

            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }

            webView.evaluateJavaScript("window.cmEditor?.setFindState(\(json));", completionHandler: nil)
        }

        private func scheduleSpellCheck(for text: String) {
            spellCheckWorkItem?.cancel()
            guard AppConstants.boolSetting(forKey: AppConstants.Keys.spellCheckEnabled, default: true) else {
                SpellCheckSync.clearMarks(on: webView)
                return
            }

            let webView = self.webView
            let work = DispatchWorkItem {
                let ranges = SpellCheckSync.findMisspellings(in: text)
                DispatchQueue.main.async { [weak self] in
                    SpellCheckSync.pushRangesToEditor(ranges, on: self?.webView ?? webView)
                }
            }
            spellCheckWorkItem = work
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }
}

private struct JSOutlineHeading: Decodable {
    let lineNumber: Int
    let level: Int
    let title: String
}
