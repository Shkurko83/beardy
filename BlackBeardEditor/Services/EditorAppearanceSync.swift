import Foundation

/// Pushes appearance settings to the CodeMirror WebView immediately (before app chrome updates).
enum EditorAppearanceSync {

    static func pushToEditor() {
        let theme = ThemeService.shared
        let css = theme.generateCSS(colors: theme.colors)
        let js = buildApplyScript(
            isDark: theme.isDarkMode,
            themeCSS: css,
            themeId: theme.currentTheme.id,
            codeThemeURL: theme.currentCodeTheme.cdnURL,
            codeThemeName: theme.currentCodeTheme.rawValue,
            codeBlockBg: theme.codeBlockBackgroundHex,
            codeBlockBorder: theme.codeBlockBorderHex,
            showLineNumbers: UserDefaults.standard.bool(forKey: AppConstants.Keys.showCodeLineNumbers),
            focusDimLines: UserDefaults.standard.bool(forKey: AppConstants.Keys.focusDimInactiveLines),
            focusHideToolbar: readingChromeActive()
        )
        NotificationCenter.default.post(name: .editorExecJS, object: EditorExecJSPayload(script: js, target: .activeTab))
    }

    static func pushLineNumbers() {
        let enabled = UserDefaults.standard.bool(forKey: AppConstants.Keys.showCodeLineNumbers)
        EditorExecJS.post("window.cmEditor?.setShowLineNumbers(\(enabled));", target: .allMounted)
    }

    static func pushFocusMode() {
        let dim = UserDefaults.standard.bool(forKey: AppConstants.Keys.focusDimInactiveLines)
        let active = readingChromeActive()
        EditorExecJS.post(
            "window.cmEditor?.setFocusMode(\(active), \(dim), \(active));",
            target: .activeTab
        )
    }

    private static func readingChromeActive() -> Bool {
        let focus = UserDefaults.standard.bool(forKey: AppConstants.Keys.focusMode)
        let viewRaw = UserDefaults.standard.string(forKey: "selectedViewMode") ?? ViewMode.edit.rawValue
        return focus || viewRaw == ViewMode.preview.rawValue
    }

    private static func buildApplyScript(
        isDark: Bool,
        themeCSS: String,
        themeId: String,
        codeThemeURL: String,
        codeThemeName: String,
        codeBlockBg: String,
        codeBlockBorder: String,
        showLineNumbers: Bool,
        focusDimLines: Bool,
        focusHideToolbar: Bool
    ) -> String {
        let escapedCSS = escapeForJS(themeCSS)
        let escapedId = escapeForJS(themeId)
        let escapedURL = escapeForJS(codeThemeURL)
        let escapedName = escapeForJS(codeThemeName)
        let escapedBg = escapeForJS(codeBlockBg)
        let escapedBorder = escapeForJS(codeBlockBorder)
        let focusActive = readingChromeActive()

        return """
        (function() {
            if (!window.cmEditor?.applyAppearance) return;
            window.cmEditor.applyAppearance({
                isDark: \(isDark),
                themeId: `\(escapedId)`,
                themeCSS: `\(escapedCSS)`,
                codeThemeURL: `\(escapedURL)`,
                codeThemeName: `\(escapedName)`,
                codeBlockBg: `\(escapedBg)`,
                codeBlockBorder: `\(escapedBorder)`,
                showLineNumbers: \(showLineNumbers),
                focusActive: \(focusActive),
                focusDimLines: \(focusDimLines),
                focusHideToolbar: \(focusHideToolbar)
            });
        })();
        """
    }

    private static func escapeForJS(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
