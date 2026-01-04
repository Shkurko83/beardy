//
//  MarkdownRenderer.swift
//  Beardy2
//
//  Created by Butt Simpson on 27.12.2025.
//

import SwiftUI
import WebKit
import Markdown

struct MarkdownRenderer: NSViewRepresentable {

    let markdown: String
    let textColor: String
    let isDark: Bool
    let codeTheme: String
    let showLineNumbers: Bool
    let scrollPosition: CGFloat
    
    // Словарь цветов для каждой темы
    private let themeBackgrounds: [String: String] = [
        "github": "#ffffff",
        "github-dark": "#0d1117",
        "monokai": "#272822",
        "dracula": "#282a36",
        "atom-one-dark": "#282c34",
        "atom-one-light": "#fafafa",
        "vs": "#ffffff",
        "vs2015": "#1e1e1e",
        "xcode": "#ffffff",
        "nord": "#2e3440",
        "tokyo-night-dark": "#1a1b26"
    ]
    
    private let themeBorders: [String: String] = [
        "github": "#d0d7de",
        "github-dark": "#30363d",
        "monokai": "#49483e",
        "dracula": "#44475a",
        "atom-one-dark": "#181a1f",
        "atom-one-light": "#eaeaeb",
        "vs": "#eeeeee",
        "vs2015": "#3e3e42",
        "xcode": "#e1e1e1",
        "nord": "#3b4252",
        "tokyo-night-dark": "#24283b"
    ]
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground") // Прозрачный фон
        return webView
    }
    
    var invertedColor: String {
        // Если textColor это HEX (напр. #FFFFFF)
        if textColor.hasPrefix("#") {
            let hex = textColor.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            if let int = UInt64(hex, radix: 16) {
                let r = (int >> 16) & 0xFF
                let g = (int >> 8) & 0xFF
                let b = int & 0xFF
                return String(format: "#%02X%02X%02X", 255 - r, 255 - g, 255 - b)
            }
        }
        // Если это не HEX, а системное имя (white, black),
        // проще вернуть противоположный в зависимости от темной темы
        return isDark ? "#FFFFFF" : "#000000"
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let compositeHash = markdown.hashValue ^ textColor.hashValue ^ codeTheme.hashValue ^ showLineNumbers.hashValue
        
        if context.coordinator.lastHash != compositeHash {
            context.coordinator.lastHash = compositeHash
            
            let processedMarkdown = markdown.components(separatedBy: .newlines)
                .map { $0.isEmpty ? "\u{00A0}" : $0 } // Добавляем неразрывный пробел в пустые строки
                .joined(separator: "\n")
            
            
            let document = Document(parsing: processedMarkdown)
            var visitor = HTMLVisitor()
            let bodyHtml = visitor.visit(document)
            
            let currentBg = themeBackgrounds[codeTheme] ?? (isDark ? "#1e1e1e" : "#ededed")
            let currentBorder = themeBorders[codeTheme] ?? (isDark ? "#333" : "#ddd")
            
            let baseFontSize: CGFloat = 14
            
            let html = """
                <html>
                <head>
                    <meta charset="UTF-8">
                    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/\(codeTheme).min.css">
                    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
                    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlightjs-line-numbers.js/2.8.0/highlightjs-line-numbers.min.js"></script>
                    
                    <style>
                        body { 
                            font-family: -apple-system, sans-serif; 
                            color: \(textColor); 
                            background-color: transparent;
                            line-height: 1.5; 
                            padding: 20px; 
                            white-space: pre-wrap !important;
                        }
                
                        pre { 
                            background: \(currentBg) !important;
                            border: 1px solid \(currentBorder);
                            border-radius: 8px;
                            margin: 1em 0;
                            overflow-x: auto;
                        }
                
                        code { 
                            display: block;
                            padding: 16px !important;
                            padding-left: \(showLineNumbers ? "0px" : "10px") !important;
                            background: transparent !important;
                            border: none !important;
                            white-space: pre;
                        }
                
                        code, code *, .hljs-ln td {
                            font-family: "SF Mono", "Menlo", monospace !important;
                            font-size: 14px !important;
                            line-height: 1.5 !important;
                        }
                
                        .hljs-ln-code {
                            padding-left: 20px !important;
                            padding-right: 16px !important;
                            padding-top: 0px !important;
                            padding-bottom: 0px !important;
                            vertical-align: top;
                            line-height: 1.5 !important;
                            white-space: pre !important;
                            word-wrap: normal !important;
                        }
                
                        .hljs {
                            color: inherit; 
                        }
                
                        /* НОМЕРА СТРОК */
                        .hljs-ln-numbers {
                            -webkit-touch-callout: none;
                            -webkit-user-select: none;
                            user-select: none;
                            text-align: right;
                            color: #858585 !important;
                            vertical-align: top;
                            padding-left: \(showLineNumbers ? "10px" : "0px") !important;
                            padding-right: 12px !important;
                            padding-top: 0px !important;
                            padding-bottom: 0px !important;
                            width: 30px !important;
                            background: \(isDark ? "rgba(255,255,255,0.03)" : "rgba(0,0,0,0.03)");
                            border-right: 1px solid \(currentBorder) !important;
                        }
                
                        .hljs-ln { border-collapse: collapse; width: 100%; }
                
                        /* --- СТИЛИ ЗАГОЛОВКОВ --- */
                        p, h1, h2, h3, h4, h5, h6, pre, ul, ol {
                             margin-top: 0;
                             display: block;
                        }
                
                        p:empty::before, h1:empty::before, h2:empty::before, h3:empty::before {
                            content: "\00a0";
                        }
                        
                        h1, h2, h3, h4, h5, h6 {
                            display: block !important;
                            clear: both !important;
                            width: 100% !important;
                            font-weight: bold !important;
                            margin-top: 12px !important;
                            margin-bottom: 8px !important;
                        }

                        /* Применяем размеры через селекторы, которые сложно перебить */
                        body #main-content h1 { font-size: \(baseFontSize + 12)px !important; }
                        body #main-content h2 { font-size: \(baseFontSize + 8)px !important; }
                        body #main-content h3 { font-size: \(baseFontSize + 4)px !important; }

                        /* Если парсер ошибся и засунул всё в <p>, добавим поддержку переносов */
                        p {
                            white-space: pre-wrap !important;
                            margin-top: 0 !important;
                            margin-bottom: 0.5em !important;
                        }

                    </style>
                </head>
                <body>
                    <div id="main-content">\(bodyHtml)</div>
                    <script>
                        hljs.highlightAll();
                        if (\(showLineNumbers)) {
                                setTimeout(function() {
                                    document.querySelectorAll('code').forEach((block) => {
                                        hljs.lineNumbersBlock(block);
                                    });
                                }, 0);
                        }
                    </script>
                </body>
                </html>
                """
            
            DispatchQueue.main.async {
                webView.loadHTMLString(html, baseURL: nil)
            }
        } else {
            let js = "window.scrollTo(0, \(scrollPosition));"
                        webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject {
        var lastHash: Int = 0
    }
}
