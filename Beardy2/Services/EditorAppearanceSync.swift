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
            focusHideToolbar: UserDefaults.standard.bool(forKey: AppConstants.Keys.focusHideToolbar)
        )
        NotificationCenter.default.post(name: .editorExecJS, object: js)
    }

    static func pushLineNumbers() {
        let enabled = UserDefaults.standard.bool(forKey: AppConstants.Keys.showCodeLineNumbers)
        NotificationCenter.default.post(
            name: .editorExecJS,
            object: "window.cmEditor?.setShowLineNumbers(\(enabled));"
        )
    }

    static func pushFocusMode() {
        let dim = UserDefaults.standard.bool(forKey: AppConstants.Keys.focusDimInactiveLines)
        let hide = UserDefaults.standard.bool(forKey: AppConstants.Keys.focusHideToolbar)
        let active = UserDefaults.standard.bool(forKey: AppConstants.Keys.focusMode)
        NotificationCenter.default.post(
            name: .editorExecJS,
            object: "window.cmEditor?.setFocusMode(\(active), \(dim), \(hide));"
        )
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
        let focusActive = UserDefaults.standard.bool(forKey: AppConstants.Keys.focusMode)

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
