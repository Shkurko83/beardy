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
        if context.coordinator.lastHash == compositeHash { return }
        context.coordinator.lastHash = compositeHash

        let document = Document(parsing: markdown)
        var visitor = HTMLVisitor()
        let bodyHtml = visitor.visit(document)

        let currentBg = themeBackgrounds[codeTheme] ?? (isDark ? "#1e1e1e" : "#ededed")
        let currentBorder = themeBorders[codeTheme] ?? (isDark ? "#333" : "#ddd")

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
                            line-height: 1.6; 
                            padding: 20px; 
                        }

                        /* ФОН И РАМКА */
                        pre { 
                            background: \(currentBg) !important;
                            border: 1px solid \(currentBorder);
                            border-radius: 8px;
                            margin: 1em 0;
                            overflow-x: auto;
                        }

                        code { 
                            display: block;
                            padding: \(showLineNumbers ? "0" : "16px") !important;
                            background: transparent !important;
                            border: none !important;
                            white-space: pre;
                        }

                        /* ФИКСАЦИЯ ШРИФТА И ВЫСОТЫ СТРОК */
                        code, code *, .hljs-ln td {
                            font-family: "SF Mono", "Menlo", monospace !important;
                            font-size: 13px !important;
                            line-height: 1.5 !important;
                        }

                        /* ГЛАВНОЕ ИСПРАВЛЕНИЕ ЦВЕТА */
                        /* Заставляем текст внутри таблицы использовать цвета темы HLJS */
                        .hljs-ln-code {
                            padding-left: 20px !important;
                            padding-right: 16px !important;
                            padding-top: \(showLineNumbers ? "16px" : "0") !important;
                            padding-bottom: \(showLineNumbers ? "16px" : "0") !important;
                            vertical-align: top;
                        }

                        /* Если текст внутри ячейки не раскрашен, принудительно даем ему цвет темы */
                        .hljs {
                            color: inherit; 
                        }

                        /* НОМЕРА СТРОК */
                        .hljs-ln-numbers {
                            -webkit-touch-callout: none;
                            -webkit-user-select: none;
                            user-select: none;
                            text-align: right;
                            color: #858585 !important; /* Цвет номеров оставляем нейтральным */
                            vertical-align: top;
                            padding-left: 12px !important;
                            padding-right: 12px !important;
                            padding-top: \(showLineNumbers ? "16px" : "0") !important;
                            width: 30px !important;
                            background: \(isDark ? "rgba(255,255,255,0.03)" : "rgba(0,0,0,0.03)");
                            border-right: 1px solid \(currentBorder) !important;
                        }

                        .hljs-ln { border-collapse: collapse; width: 100%; }
                    </style>
                </head>
                <body>
                    \(bodyHtml)
                    <script>
                        // Обязательный порядок:
                        // 1. Сначала подсвечиваем весь код
                        hljs.highlightAll();

                        if (\(showLineNumbers)) {
                                setTimeout(function() {
                                    document.querySelectorAll('code').forEach((block) => {
                                        hljs.lineNumbersBlock(block); // Потом нумеруем
                                    });
                                }, 50); // Небольшая задержка для стабильности
                        }
                    </script>
                </body>
                </html>
                """
        
        DispatchQueue.main.async {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
    
    
//    func updateNSView(_ webView: WKWebView, context: Context) {
//        let compositeHash = markdown.hashValue ^ textColor.hashValue ^ codeTheme.hashValue ^ showLineNumbers.hashValue
//        if context.coordinator.lastHash == compositeHash { return }
//        context.coordinator.lastHash = compositeHash
//        
//        let document = Document(parsing: markdown)
//        var visitor = HTMLVisitor()
//        let bodyHtml = visitor.visit(document)
//        
//        let currentBg = themeBackgrounds[codeTheme] ?? (isDark ? "#1e1e1e" : "#ededed")
//        let currentBorder = themeBorders[codeTheme] ?? (isDark ? "#333" : "#ddd")
//        
//        let html = """
//                <html>
//                <head>
//                    <meta charset="UTF-8">
//                    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/\(codeTheme).min.css">
//                    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
//                    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlightjs-line-numbers.js/2.8.0/highlightjs-line-numbers.min.js"></script>
//                    
//                    <style>
//                        body { 
//                            font-family: -apple-system, sans-serif; 
//                            color: \(textColor); 
//                            background-color: transparent;
//                            line-height: 1.6; 
//                            padding: 20px; 
//                        }
//                        
//                        pre { 
//                            background: transparent !important; 
//                            margin: 1em 0;
//                            padding: 0;
//                        }
//                
//                        code { 
//                            font-family: "SF Mono", "Menlo", monospace; 
//                            font-size: 0.9em; 
//                            display: block;
//                            padding: 16px !important;
//                            border-radius: 8px;
//                            white-space: \(showLineNumbers ? "normal" : "pre");
//                            overflow-x: auto;
//                            
//                            /* Динамические цвета из Swift */
//                            background-color: \(currentBg) !important; 
//                            border: 1px solid \(currentBorder);
//                        }
//                
//                        .hljs-ln-numbers {
//                            width: 30px;
//                            min-width: 30px;
//                        }
//                
//                        table { border-collapse: collapse; width: 100%; margin: 1em 0; }
//                        th, td { border: 1px solid \(isDark ? "#444" : "#ccc"); padding: 8px; }
//                    </style>
//                </head>
//                <body>
//                    \(bodyHtml)
//                    <script>
//                        hljs.configure({ ignoreUnescapedHTML: true });
//                        hljs.highlightAll();
//                        function applyLineNumbers() {
//                            if (\(showLineNumbers)) {
//                                document.querySelectorAll('code.hljs').forEach((el) => {
//                                    hljs.lineNumbersBlock(el);
//                                });
//                            }
//                        }
//                
//                        // Запускаем сразу
//                        applyLineNumbers();
//                    </script>
//                </body>
//                </html>
//                """
//        DispatchQueue.main.async {
//            webView.loadHTMLString(html, baseURL: nil)
//        }
//    }
//    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject {
        var lastHash: Int = 0
    }
}
