import Foundation

/// Pushes Settings → Editor preferences to the markdown textarea WebView.
enum EditorSettingsSync {

    static func pushToEditor() {
        let fontSize = AppConstants.doubleSetting(
            forKey: AppConstants.Keys.editorFontSize,
            default: Double(AppConstants.Defaults.fontSize)
        )
        let lineHeight = AppConstants.doubleSetting(
            forKey: AppConstants.Keys.editorLineHeight,
            default: Double(AppConstants.Defaults.lineHeight)
        )
        let fontFamily = UserDefaults.standard.string(forKey: AppConstants.Keys.editorFontFamily)
            ?? AppConstants.Defaults.fontFamily
        let showLineNumbers = AppConstants.boolSetting(forKey: AppConstants.Keys.showLineNumbers, default: false)
        var highlightCurrentLine = AppConstants.boolSetting(forKey: AppConstants.Keys.highlightCurrentLine, default: true)
        if !showLineNumbers {
            if AppConstants.boolSetting(forKey: AppConstants.Keys.highlightCurrentLine, default: true) {
                UserDefaults.standard.set(false, forKey: AppConstants.Keys.highlightCurrentLine)
            }
            highlightCurrentLine = false
        }
        let indentSize = AppConstants.intSetting(forKey: AppConstants.Keys.indentSize, default: AppConstants.Defaults.tabSize)
        let useSpacesForTabs = AppConstants.boolSetting(forKey: AppConstants.Keys.useSpacesForTabs, default: true)

        let escapedFamily = escapeForJS(fontFamily)
        let script = """
        (function() {
            if (!window.cmEditor?.setEditorPreferences) return;
            window.cmEditor.setEditorPreferences({
                fontFamily: `\(escapedFamily)`,
                fontSize: \(fontSize),
                lineHeight: \(lineHeight),
                showLineNumbers: \(showLineNumbers),
                highlightCurrentLine: \(highlightCurrentLine),
                indentSize: \(indentSize),
                useSpacesForTabs: \(useSpacesForTabs)
            });
        })();
        """
        NotificationCenter.default.post(name: .editorExecJS, object: script)
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
