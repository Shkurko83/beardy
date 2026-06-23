
import SwiftUI
import WebKit

/// Dedicated WKWebView for a single editor tab (mounted lazily, kept warm while in LRU).
struct CodeMirrorWebView: NSViewRepresentable {
    let tabID: UUID
    let isSelected: Bool
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let currentDocumentURL: URL?
    let isDark: Bool
    let viewMode: ViewMode
    let editorTheme: EditorThemeIdentity
    let codeBlockTheme: CodeTheme
    let appearanceToken: String

    private static let sessionGeneration: UInt = 1
    fileprivate static let inlineEditorContentLimit = 350_000
    private static let contentImportChunkSize = 900_000

    /// Swift model for this tab — never use the shared `text` binding for load/boot.
    fileprivate func tabModelContent() -> String {
        DocumentManager.shared?.tabs.first(where: { $0.id == tabID })?.document.content ?? ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let preferences = config.preferences
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

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        let tabID = coordinator.parent.tabID
        EditorWebViewPool.shared.unregister(tabID: tabID)
        DocumentManager.shared?.markTabEditorEvicted(tabID)
        NotificationCenter.default.removeObserver(coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        webView.isHidden = false

        guard context.coordinator.pageLoaded else { return }

        if let docURL = currentDocumentURL {
            context.coordinator.lastDocumentURL = docURL
        }

        let modelText = tabModelContent()
        if !context.coordinator.isUpdatingFromJS && context.coordinator.lastKnownText != modelText {
            pushContentToEditor(modelText, webView: webView, coordinator: context.coordinator)
        }

        updateThemeAndMode(webView, context: context)
        syncDocumentPath(webView, coordinator: context.coordinator)
    }

    private func syncDocumentPath(_ webView: WKWebView, coordinator: Coordinator) {
        let docPath = currentDocumentURL?
            .deletingLastPathComponent()
            .path ?? ""
        guard coordinator.lastDocumentBasePath != docPath else { return }
        coordinator.lastDocumentBasePath = docPath
        let escaped = escapeForJS(docPath)
        webView.evaluateJavaScript("window.cmEditor?.setDocumentPath(`\(escaped)`);", completionHandler: nil)
    }

    private func updateThemeAndMode(_ webView: WKWebView, context: Context) {
        guard context.coordinator.pageLoaded else { return }

        if context.coordinator.lastAppearanceToken != appearanceToken {
            context.coordinator.lastAppearanceToken = appearanceToken
            applyAppearance(to: webView, coordinator: context.coordinator)
        }

        if context.coordinator.lastViewMode != viewMode {
            context.coordinator.lastViewMode = viewMode
            let mode = jsViewModeName(viewMode)
            webView.evaluateJavaScript("window.cmEditor?.setViewMode('\(mode)');", completionHandler: nil)
        }
    }

    fileprivate func applyAppearance(to webView: WKWebView, coordinator: Coordinator) {
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

    private func jsViewModeName(_ mode: ViewMode) -> String {
        switch mode {
        case .edit: return "edit"
        case .live: return "live"
        case .preview: return "preview"
        case .split: return "split"
        case .experimental: return "experimental"
        case .ySplit: return "ysplit"
        case .diff: return "preview"
        }
    }

    fileprivate func pushContentToEditor(
        _ text: String,
        webView: WKWebView,
        coordinator: Coordinator,
        completion: (() -> Void)? = nil
    ) {
        let loadToken = coordinator.beginContentImportSession()
        coordinator.beginDocumentLoad(expectedCharacterCount: text.count)
        coordinator.lastKnownText = text
        let generation = Self.sessionGeneration

        if text.count <= Self.inlineEditorContentLimit {
            let escapedText = escapeForJS(text)
            webView.evaluateJavaScript(
                "window.cmEditor?.updateContentForLoad?.(`\(escapedText)`, \(generation));"
            ) { _, _ in
                guard coordinator.isContentImportActive(loadToken) else { return }
                completion?()
            }
            return
        }

        guard let data = text.data(using: .utf8) else {
            coordinator.cancelContentImport()
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

        webView.evaluateJavaScript(
            "window.cmEditor?.beginContentImport(\(chunks.count), \(generation));"
        ) { _, _ in
            guard coordinator.isContentImportActive(loadToken) else { return }
            self.appendContentImportChunks(
                chunks,
                token: loadToken,
                generation: generation,
                startingAt: 0,
                webView: webView,
                coordinator: coordinator
            ) {
                guard coordinator.isContentImportActive(loadToken) else { return }
                webView.evaluateJavaScript("window.cmEditor?.finishContentImport(\(generation));") { _, _ in
                    guard coordinator.isContentImportActive(loadToken) else { return }
                    coordinator.finishContentImportSession(loadToken)
                    completion?()
                }
            }
        }
    }

    private func appendContentImportChunks(
        _ chunks: [String],
        token: UInt,
        generation: UInt,
        startingAt index: Int,
        webView: WKWebView,
        coordinator: Coordinator,
        completion: @escaping () -> Void
    ) {
        guard coordinator.isContentImportActive(token) else { return }
        guard index < chunks.count else {
            completion()
            return
        }

        let escaped = escapeForJS(chunks[index])
        let script = "window.cmEditor?.appendContentImportChunk(\(index), `\(escaped)`, \(generation));"
        webView.evaluateJavaScript(script) { _, _ in
            guard coordinator.isContentImportActive(token) else { return }
            self.appendContentImportChunks(
                chunks,
                token: token,
                generation: generation,
                startingAt: index + 1,
                webView: webView,
                coordinator: coordinator,
                completion: completion
            )
        }
    }

    fileprivate func finishEditorSetup(webView: WKWebView, viewMode: String, coordinator: Coordinator) {
        webView.evaluateJavaScript("window.cmEditor?.setViewMode('\(viewMode)');")

        let isSwapped = UserDefaults.standard.bool(forKey: "editorPanesSwapped")
        webView.evaluateJavaScript("window.cmEditor?.setSwapped(\(isSwapped));")

        let syncScroll = AppConstants.isPreviewSyncScrollEnabled
        webView.evaluateJavaScript("window.cmEditor?.setSyncScroll(\(syncScroll));")
        EditorSettingsSync.pushToEditor()
        TypingSettingsSync.pushToEditor()

        let modelText = tabModelContent()
        coordinator.pageLoaded = true
        EditorWebViewPool.shared.register(tabID: tabID, coordinator: coordinator)
        coordinator.flushPendingExecScripts(on: webView)
        coordinator.lastKnownText = modelText
        coordinator.lastAppearanceToken = appearanceToken
        applyAppearance(to: webView, coordinator: coordinator)
        syncDocumentPath(webView, coordinator: coordinator)
        if isSelected {
            webView.evaluateJavaScript("window.cmEditor?.publishOutlineHeadings?.();")
        }
    }

    fileprivate func escapeForJS(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func setEditorTabSession(webView: WKWebView, completion: @escaping () -> Void) {
        let script = """
        window.cmEditor?.setEditorTabSession?.({ tabId: '\(tabID.uuidString)', generation: \(Self.sessionGeneration) });
        """
        webView.evaluateJavaScript(script) { _, _ in
            completion()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: CodeMirrorWebView
        var webView: WKWebView?
        var isUpdatingFromJS = false
        var lastKnownText = ""
        var lastViewMode: ViewMode?
        var pageLoaded = false
        var lastAppearanceToken: String?
        var lastDocumentURL: URL?
        var lastDocumentBasePath: String?
        private var pendingExecScripts: [(script: String, target: EditorExecTarget)] = []
        private var spellCheckWorkItem: DispatchWorkItem?
        private var documentLoadExpectedCount = 0
        private var documentLoadStartedAt: Date?
        private var contentLoadToken: UInt = 0
        private var activeContentLoadToken: UInt = 0
        private var flushHandler: ((String) -> Void)?

        init(_ parent: CodeMirrorWebView) {
            self.parent = parent
            self.lastKnownText = parent.tabModelContent()
            self.lastAppearanceToken = parent.appearanceToken
        }

        func evaluateJS(_ script: String) {
            guard pageLoaded, let webView else {
                pendingExecScripts.append((script, .tab(parent.tabID)))
                return
            }
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func pushContentFromNative(_ content: String) {
            guard let webView else { return }
            parent.pushContentToEditor(content, webView: webView, coordinator: self)
        }

        func flushEditorContent(expectedGeneration: UInt, fallback: String, completion: @escaping (String) -> Void) {
            var finished = false
            let finish: (String) -> Void = { value in
                guard !finished else { return }
                finished = true
                self.flushHandler = nil
                completion(value)
            }
            flushHandler = finish
            evaluateJS("window.cmEditor?.flushEditorContentForNative?.();")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard !finished else { return }
                finish(fallback)
            }
        }

        func syncForActivation(documentManager: DocumentManager) {
            guard let webView, pageLoaded else { return }
            if lastAppearanceToken != parent.appearanceToken {
                lastAppearanceToken = parent.appearanceToken
                parent.applyAppearance(to: webView, coordinator: self)
            }
            let mode = parent.jsViewModeName(documentManager.viewMode)
            if lastViewMode != documentManager.viewMode {
                webView.evaluateJavaScript("window.cmEditor?.setViewMode('\(mode)');", completionHandler: nil)
                lastViewMode = documentManager.viewMode
            } else {
                webView.evaluateJavaScript("window.cmEditor?.onTabActivated?.();", completionHandler: nil)
            }
            let syncScroll = AppConstants.isPreviewSyncScrollEnabled
            webView.evaluateJavaScript("window.cmEditor?.setSyncScroll(\(syncScroll));", completionHandler: nil)
            webView.evaluateJavaScript("window.cmEditor?.publishOutlineHeadings?.();", completionHandler: nil)
        }

        func cancelContentImport() {
            contentLoadToken &+= 1
            activeContentLoadToken = 0
            endDocumentLoad()
        }

        func beginContentImportSession() -> UInt {
            contentLoadToken &+= 1
            activeContentLoadToken = contentLoadToken
            return contentLoadToken
        }

        func isContentImportActive(_ token: UInt) -> Bool {
            token != 0 && token == activeContentLoadToken && token == contentLoadToken
        }

        func finishContentImportSession(_ token: UInt) {
            guard token == activeContentLoadToken else { return }
            activeContentLoadToken = 0
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
            let tabContent = parent.tabModelContent()
            let useImport = tabContent.count > CodeMirrorWebView.inlineEditorContentLimit

            let completeSetup = {
                self.parent.finishEditorSetup(webView: webView, viewMode: viewMode, coordinator: self)
            }

            let loadEditorContent = {
                if useImport {
                    let initScript = "window.initializeEditor('', \(self.parent.isDark), null);"
                    webView.evaluateJavaScript(initScript) { _, error in
                        if error != nil { return }
                        self.parent.pushContentToEditor(tabContent, webView: webView, coordinator: self) {
                            completeSetup()
                        }
                    }
                    return
                }

                let escapedText = self.parent.escapeForJS(tabContent)
                let initScript = "window.initializeEditor(`\(escapedText)`, \(self.parent.isDark), '\(viewMode)');"
                webView.evaluateJavaScript(initScript) { _, error in
                    if error != nil { return }
                    completeSetup()
                }
            }

            parent.setEditorTabSession(webView: webView) {
                loadEditorContent()
            }
        }

        fileprivate func flushPendingExecScripts(on webView: WKWebView) {
            let scripts = pendingExecScripts
            pendingExecScripts.removeAll()
            for entry in scripts where handlesTarget(entry.target) {
                webView.evaluateJavaScript(entry.script, completionHandler: nil)
            }
        }

        func handlesTarget(_ target: EditorExecTarget) -> Bool {
            switch target {
            case .allMounted:
                return true
            case .activeTab:
                return parent.isSelected
            case .tab(let id):
                return parent.tabID == id
            }
        }

        @objc func handleThemeDidChange(_ notification: Notification) {
            guard pageLoaded, parent.isSelected else { return }
            lastAppearanceToken = parent.appearanceToken
            if let webView {
                parent.applyAppearance(to: webView, coordinator: self)
            }
        }

        @objc func handleCodeThemeDidChange(_ notification: Notification) {
            handleThemeDidChange(notification)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "logging" { return }

            if message.name == "editorContentFlush" {
                DispatchQueue.main.async {
                    if let flush = Self.parseEditorFlushMessage(message.body) {
                        guard flush.tabID == self.parent.tabID else { return }
                        self.flushHandler?(flush.content)
                    }
                }
            }

            if message.name == "contentChanged" {
                guard let payload = Self.parseEditorContentMessage(message.body),
                      payload.tabID == self.parent.tabID,
                      DocumentManager.shared?.shouldAcceptEditorContent(payload, source: .userEdit) == true else {
                    return
                }
                if shouldIgnoreContentChange(payload.content) { return }
                lastKnownText = payload.content
                scheduleSpellCheck(for: payload.content)
                DispatchQueue.main.async {
                    DocumentManager.shared?.applyEditorContent(
                        tabID: self.parent.tabID,
                        content: payload.content,
                        recordUndo: self.parent.isSelected
                    )
                    if self.parent.isSelected {
                        self.isUpdatingFromJS = true
                        self.parent.text = payload.content
                        self.isUpdatingFromJS = false
                    }
                }
            }

            if message.name == "documentContentLoaded" {
                guard let payload = Self.parseEditorContentMessage(message.body),
                      payload.tabID == self.parent.tabID,
                      DocumentManager.shared?.shouldAcceptEditorContent(payload, source: .documentLoaded) == true else {
                    return
                }
                endDocumentLoad()
                lastKnownText = payload.content
                DispatchQueue.main.async {
                    DocumentManager.shared?.markTabEditorReady(self.parent.tabID)
                    if self.parent.isSelected {
                        DocumentManager.shared?.refreshStatisticsForCurrentTab()
                    }
                }
            }

            if message.name == "spellCheckRequest", let text = message.body as? String, parent.isSelected {
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
               let action = body["action"] as? String, parent.isSelected {
                let snapshot = body["snapshot"] as? String
                DispatchQueue.main.async {
                    if action == "undo" {
                        DocumentManager.shared?.undo(editorSnapshot: snapshot)
                    } else if action == "redo" {
                        DocumentManager.shared?.redo(editorSnapshot: snapshot)
                    }
                }
            }

            if message.name == "outlineHeadings", parent.isSelected {
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
            guard let payload = EditorExecJSPayload.from(notification) else { return }
            guard handlesTarget(payload.target) else { return }
            guard pageLoaded, let webView else {
                pendingExecScripts.append((payload.script, payload.target))
                return
            }
            webView.evaluateJavaScript(payload.script, completionHandler: nil)
        }

        @objc func handleFindUpdate(_ notification: Notification) {
            guard parent.isSelected, pageLoaded, let webView else { return }
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
            guard parent.isSelected else { return }
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

        private static func parseEditorContentMessage(_ body: Any) -> EditorContentMessage? {
            guard let dict = body as? [String: Any],
                  let tabIdStr = dict["tabId"] as? String,
                  let tabID = UUID(uuidString: tabIdStr),
                  let content = dict["content"] as? String else {
                return nil
            }
            let generation: UInt
            if let value = dict["generation"] as? UInt {
                generation = value
            } else if let value = dict["generation"] as? Int, value >= 0 {
                generation = UInt(value)
            } else if let value = dict["generation"] as? Double, value >= 0 {
                generation = UInt(value)
            } else {
                return nil
            }
            return EditorContentMessage(tabID: tabID, generation: generation, content: content)
        }

        private static func parseEditorFlushMessage(_ body: Any) -> EditorFlushMessage? {
            guard let dict = body as? [String: Any],
                  let tabIdStr = dict["tabId"] as? String,
                  let tabID = UUID(uuidString: tabIdStr),
                  let content = dict["content"] as? String else {
                return nil
            }
            let generation: UInt
            if let value = dict["generation"] as? UInt {
                generation = value
            } else if let value = dict["generation"] as? Int, value >= 0 {
                generation = UInt(value)
            } else if let value = dict["generation"] as? Double, value >= 0 {
                generation = UInt(value)
            } else {
                return nil
            }
            return EditorFlushMessage(tabID: tabID, generation: generation, content: content)
        }
    }
}

private struct JSOutlineHeading: Decodable {
    let lineNumber: Int
    let level: Int
    let title: String
}
