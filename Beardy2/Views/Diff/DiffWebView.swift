import SwiftUI
import WebKit

struct DiffWebView: NSViewRepresentable {
    let html: String
    let focusedChangeIndex: Int

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(ImageSchemeHandler(), forURLScheme: "beardy")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            let loadNewHTML = {
                context.coordinator.lastHTML = html
                context.coordinator.pageLoaded = false
                let baseURL = Bundle.main.resourceURL
                webView.loadHTMLString(html, baseURL: baseURL)
            }

            if context.coordinator.pageLoaded {
                webView.evaluateJavaScript("JSON.stringify(captureDiffScrollAnchor())") { value, _ in
                    if let json = value as? String, !json.isEmpty, json != "null" {
                        context.coordinator.scrollAnchorJSON = json
                    }
                    loadNewHTML()
                }
            } else {
                loadNewHTML()
            }
        } else if context.coordinator.pageLoaded,
                  context.coordinator.lastFocusedIndex != focusedChangeIndex,
                  focusedChangeIndex > 0 {
            context.coordinator.scrollToChange(focusedChangeIndex, in: webView)
            context.coordinator.lastFocusedIndex = focusedChangeIndex
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(focusedChangeIndex: focusedChangeIndex)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        var lastHTML: String?
        var lastFocusedIndex: Int = 0
        var pageLoaded = false
        var scrollAnchorJSON: String?
        let initialFocusIndex: Int

        init(focusedChangeIndex: Int) {
            self.initialFocusIndex = focusedChangeIndex
            self.lastFocusedIndex = focusedChangeIndex
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            if let json = scrollAnchorJSON {
                let script = """
                window.__diffScrollRestore = \(json);
                scheduleDiffScrollRestore();
                """
                webView.evaluateJavaScript(script, completionHandler: nil)
                scrollAnchorJSON = nil
            } else if initialFocusIndex > 0 {
                scrollToChange(initialFocusIndex, in: webView)
            }
        }

        func scrollToChange(_ index: Int, in webView: WKWebView) {
            let script = "scrollToChangeIndex(\(index));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
