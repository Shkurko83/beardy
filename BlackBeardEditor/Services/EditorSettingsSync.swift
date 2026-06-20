import Foundation

/// Pushes document typography and editor preferences to the markdown WebView.
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
