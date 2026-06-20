import AppKit
import Foundation
import WebKit

/// Native spell checking for the WKWebView markdown textarea (WebKit does not draw squiggles reliably).
enum SpellCheckSync {

    struct TextRange: Codable {
        let from: Int
        let to: Int
    }

    private static func spellingLanguage() -> String {
        let language = NSSpellChecker.shared.language()
        if !language.isEmpty {
            return language
        }
        if let code = Locale.current.language.languageCode?.identifier, !code.isEmpty {
            return code
        }
        return "en"
    }

    static func findMisspellings(in text: String) -> [TextRange] {
        guard !text.isEmpty else { return [] }

        let scanLimit = 400_000
        let scanText = text.count > scanLimit ? String(text.prefix(scanLimit)) : text

        let checker = NSSpellChecker.shared
        let language = spellingLanguage()
        let nsLength = (scanText as NSString).length
        var location = 0
        var results: [TextRange] = []

        while location < nsLength {
            let misspelled = checker.checkSpelling(
                of: scanText,
                startingAt: location,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            )
            guard misspelled.location != NSNotFound else { break }

            results.append(TextRange(
                from: misspelled.location,
                to: misspelled.location + misspelled.length
            ))
            location = misspelled.upperBound
        }

        return results
    }

    static func clearMarks(on webView: WKWebView?) {
        pushRangesToEditor([], on: webView)
    }

    static func pushRangesToEditor(_ ranges: [TextRange], on webView: WKWebView?) {
        guard let data = try? JSONEncoder().encode(ranges),
              let json = String(data: data, encoding: .utf8) else { return }

        let script = "window.cmEditor?.setSpellCheckRanges(\(json));"

        if let webView {
            webView.evaluateJavaScript(script, completionHandler: nil)
        } else {
            NotificationCenter.default.post(name: .editorExecJS, object: """
            (function() {
                if (!window.cmEditor?.setSpellCheckRanges) return;
                window.cmEditor.setSpellCheckRanges(\(json));
            })();
            """)
        }
    }
}
