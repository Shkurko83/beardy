//
//  ImageSchemeHandler.swift
//  Beardy2
//
//  Created by Butt Simpson on 21.04.2026.
//

import WebKit

class ImageSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let filePath = ImageInsertionHelper.localPath(fromBeardyURL: requestURL) else {
            urlSchemeTask.didFailWithError(NSError(domain: "ImageSchemeHandler", code: 404))
            return
        }

        let fileURL = URL(fileURLWithPath: filePath)
        let imageData = loadImageData(from: fileURL)

        guard let imageData else {
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
            url: requestURL,
            mimeType: mimeType,
            expectedContentLength: imageData.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(imageData)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func loadImageData(from fileURL: URL) -> Data? {
        if let resolvedURL = SecurityBookmarkStore.resolveURL(path: fileURL.path) {
            let accessed = resolvedURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { resolvedURL.stopAccessingSecurityScopedResource() }
            }
            if let data = try? Data(contentsOf: resolvedURL) {
                return data
            }
        }

        let accessed = ImageInsertionHelper.startAccessing(url: fileURL)
        defer {
            if accessed { fileURL.stopAccessingSecurityScopedResource() }
        }
        return try? Data(contentsOf: fileURL)
    }
}
