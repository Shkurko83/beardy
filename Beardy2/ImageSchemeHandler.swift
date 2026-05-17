//
//  ImageSchemeHandler.swift
//  Beardy2
//
//  Created by Butt Simpson on 21.04.2026.
//

import WebKit

class ImageSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              var filePath = url.absoluteString
                .replacingOccurrences(of: "beardy://localhost", with: "")
                .removingPercentEncoding else {
            urlSchemeTask.didFailWithError(NSError(domain: "ImageSchemeHandler", code: 404))
            return
        }

        let fileURL = URL(fileURLWithPath: filePath)

        // Пробуем получить доступ через сохранённый bookmark
        let bookmarkKey = "bookmark_\(fileURL.path)"
        var data: Data?

        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = resolvedURL.startAccessingSecurityScopedResource()
                data = try? Data(contentsOf: resolvedURL)
                resolvedURL.stopAccessingSecurityScopedResource()

                // Обновляем stale bookmark
                if isStale, let newBookmark = try? resolvedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(newBookmark, forKey: bookmarkKey)
                }
            }
        }

        // Fallback — прямое чтение (работает если файл ещё в памяти)
        if data == nil {
            data = try? Data(contentsOf: fileURL)
        }

        guard let imageData = data else {
            urlSchemeTask.didFailWithError(NSError(domain: "ImageSchemeHandler", code: 404))
            return
        }

        let ext = fileURL.pathExtension.lowercased()
        let mimeType: String
        switch ext {
        case "jpg", "jpeg": mimeType = "image/jpeg"
        case "png":         mimeType = "image/png"
        case "gif":         mimeType = "image/gif"
        case "webp":        mimeType = "image/webp"
        case "svg":         mimeType = "image/svg+xml"
        default:            mimeType = "application/octet-stream"
        }

        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: imageData.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(imageData)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
