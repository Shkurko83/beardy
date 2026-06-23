import Foundation

/// Pushes Settings → Typing preferences to the markdown textarea WebView.
enum TypingSettingsSync {

    static func migrateLegacySettingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AppConstants.Keys.typographicPunctuationEnabled) == nil else { return }

        let legacyQuotes = AppConstants.boolSetting(forKey: AppConstants.Keys.smartQuotesEnabled, default: false)
        let legacyDashes = AppConstants.boolSetting(forKey: AppConstants.Keys.smartDashesEnabled, default: false)
        defaults.set(legacyQuotes || legacyDashes, forKey: AppConstants.Keys.typographicPunctuationEnabled)
    }

    static func pushToEditor() {
        let spellCheck = AppConstants.boolSetting(forKey: AppConstants.Keys.spellCheckEnabled, default: true)
        let grammarCheck = AppConstants.boolSetting(forKey: AppConstants.Keys.grammarCheckEnabled, default: true)
        let autoCapitalization = AppConstants.boolSetting(
            forKey: AppConstants.Keys.autoCapitalizationEnabled,
            default: false
        )
        let typographicPunctuation = AppConstants.boolSetting(
            forKey: AppConstants.Keys.typographicPunctuationEnabled,
            default: false
        )
        let continueListsOnEnter = AppConstants.boolSetting(
            forKey: AppConstants.Keys.continueListsOnEnter,
            default: true
        )
        let continueBlockquoteOnEnter = AppConstants.boolSetting(
            forKey: AppConstants.Keys.continueBlockquoteOnEnter,
            default: true
        )
        let smartPasteURLs = AppConstants.boolSetting(
            forKey: AppConstants.Keys.smartPasteURLs,
            default: true
        )
        let autoPairBrackets = AppConstants.boolSetting(
            forKey: AppConstants.Keys.autoPairBrackets,
            default: true
        )
        let autoPairQuotes = AppConstants.boolSetting(
            forKey: AppConstants.Keys.autoPairQuotes,
            default: true
        )
        let autoCloseMarkdown = AppConstants.boolSetting(
            forKey: AppConstants.Keys.autoCloseMarkdown,
            default: true
        )

        let script = """
        (function() {
            if (!window.cmEditor?.setTypingPreferences) return;
            window.cmEditor.setTypingPreferences({
                spellCheckEnabled: \(spellCheck),
                grammarCheckEnabled: \(grammarCheck),
                autoCapitalizationEnabled: \(autoCapitalization),
                typographicPunctuation: \(typographicPunctuation),
                continueListsOnEnter: \(continueListsOnEnter),
                continueBlockquoteOnEnter: \(continueBlockquoteOnEnter),
                smartPasteURLs: \(smartPasteURLs),
                autoPairBrackets: \(autoPairBrackets),
                autoPairQuotes: \(autoPairQuotes),
                autoCloseMarkdown: \(autoCloseMarkdown)
            });
        })();
        """
        EditorExecJS.post(script, target: .allMounted)

        if spellCheck {
            let refresh = """
            (function() {
                if (window.cmEditor?.requestSpellCheckRefresh) window.cmEditor.requestSpellCheckRefresh();
            })();
            """
            EditorExecJS.post(refresh, target: .activeTab)
        } else {
            SpellCheckSync.clearMarks(on: nil)
        }
    }
}

enum TypingSaveTransform {

    static func applyingSavePreferences(to content: String) -> String {
        var text = content

        if AppConstants.boolSetting(forKey: AppConstants.Keys.trimTrailingWhitespaceOnSave, default: true) {
            text = text.trimmingTrailingWhitespace
        }

        if AppConstants.boolSetting(forKey: AppConstants.Keys.insertFinalNewlineOnSave, default: true),
           !text.isEmpty,
           !text.hasSuffix("\n") {
            text += "\n"
        }

        return text
    }
}
