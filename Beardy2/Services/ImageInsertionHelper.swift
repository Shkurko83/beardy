import Foundation

enum ImageAlignmentOption: Int {
    case none = 0
    case left = 1
    case center = 2
    case right = 3
}

enum ImagePathStrategy {
    /// `./image.png` рядом с документом (как Typora по умолчанию)
    case copyBesideDocument
    /// Абсолютный путь к исходному файлу
    case useOriginalPath
}

enum ImageInsertionError: LocalizedError {
    case copyFailed(String)
    case documentNotSaved
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let detail):
            return "Could not copy image: \(detail)"
        case .documentNotSaved:
            return "Save the document first to copy images into its folder"
        case .readFailed(let detail):
            return "Could not read image: \(detail)"
        }
    }
}

enum ImageInsertionHelper {

    static let copyImagesToDocumentFolderKey = "copyImagesToDocumentFolder"

    /// Как в Typora: по умолчанию копировать в папку с .md
    static var copyImagesToDocumentFolder: Bool {
        get {
            if UserDefaults.standard.object(forKey: copyImagesToDocumentFolderKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: copyImagesToDocumentFolderKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: copyImagesToDocumentFolderKey)
        }
    }

    private static let documentBookmarkPrefix = "doc_bookmark_"

    static func saveSecurityBookmark(for url: URL) {
        SecurityBookmarkStore.saveBookmark(for: url)
    }

    static func startAccessing(url: URL) -> Bool {
        if SecurityBookmarkStore.beginAccess(path: url.path) != nil {
            return true
        }
        return url.startAccessingSecurityScopedResource()
    }

    static func imagePath(
        from sourceURL: URL,
        documentURL: URL?,
        strategy: ImagePathStrategy
    ) throws -> String {
        switch strategy {
        case .useOriginalPath:
            return sourceURL.path
        case .copyBesideDocument:
            return try prepareImageReference(sourceURL: sourceURL, documentURL: documentURL).markdownPath
        }
    }

    static func imagePath(
        from data: Data,
        suggestedFilename: String,
        documentURL: URL?,
        strategy: ImagePathStrategy
    ) throws -> String {
        let ext = (suggestedFilename as NSString).pathExtension
        let filename = ext.isEmpty ? "\((suggestedFilename as NSString).deletingPathExtension).png" : suggestedFilename

        switch strategy {
        case .useOriginalPath:
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: temp, options: .atomic)
            saveSecurityBookmark(for: temp)
            return temp.path
        case .copyBesideDocument:
            return try saveImageData(data, suggestedName: filename, documentURL: documentURL).markdownPath
        }
    }

    static func prepareImageReference(
        sourceURL: URL,
        documentURL: URL?
    ) throws -> (markdownPath: String, fileURL: URL) {
        saveSecurityBookmark(for: sourceURL)

        guard let docURL = documentURL else {
            throw ImageInsertionError.documentNotSaved
        }

        let docDir = docURL.deletingLastPathComponent()
        let destURL = uniqueDestination(in: docDir, preferredName: sourceURL.lastPathComponent)

        if destURL.standardizedFileURL.path == sourceURL.standardizedFileURL.path {
            saveSecurityBookmark(for: destURL)
            return ("./\(destURL.lastPathComponent)", destURL)
        }

        let sourceAccess = startAccessing(url: sourceURL)
        defer {
            if sourceAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        try SecurityBookmarkStore.withDocumentFolderAccess(documentURL: docURL) {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.removeItem(at: destURL)
            }

            do {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            } catch {
                let raw = try Data(contentsOf: sourceURL)
                try raw.write(to: destURL, options: .atomic)
            }

            guard FileManager.default.fileExists(atPath: destURL.path) else {
                throw ImageInsertionError.copyFailed("file was not created next to the document")
            }
        }

        saveSecurityBookmark(for: destURL)
        return ("./\(destURL.lastPathComponent)", destURL)
    }

    static func saveImageData(
        _ data: Data,
        suggestedName: String,
        documentURL: URL?
    ) throws -> (markdownPath: String, fileURL: URL) {
        guard let docURL = documentURL else {
            throw ImageInsertionError.documentNotSaved
        }

        let ext = (suggestedName as NSString).pathExtension
        let filename: String
        if ext.isEmpty {
            filename = "\((suggestedName as NSString).deletingPathExtension).png"
        } else {
            filename = suggestedName
        }

        let docDir = docURL.deletingLastPathComponent()
        let destURL = uniqueDestination(in: docDir, preferredName: filename)

        try SecurityBookmarkStore.withDocumentFolderAccess(documentURL: docURL) {
            try data.write(to: destURL, options: .atomic)
        }
        saveSecurityBookmark(for: destURL)
        return ("./\(destURL.lastPathComponent)", destURL)
    }

    static func uniqueDestination(in directory: URL, preferredName: String) -> URL {
        var dest = directory.appendingPathComponent(preferredName)
        guard FileManager.default.fileExists(atPath: dest.path) else { return dest }

        let base = dest.deletingPathExtension().lastPathComponent
        let ext = dest.pathExtension
        var counter = 1

        while FileManager.default.fileExists(atPath: dest.path) {
            let name = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            dest = directory.appendingPathComponent(name)
            counter += 1
        }
        return dest
    }

    static func buildMarkdown(
        imagePath: String,
        alt: String,
        title: String = "",
        widthPercent: Int = 100,
        alignment: ImageAlignmentOption = .none
    ) -> String {
        let safeAlt = alt.isEmpty ? "image" : alt
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let titleAttr = title.isEmpty ? "" : " \"\(escapedTitle)\""

        if widthPercent == 100 && alignment == .none {
            let linkPath = markdownLinkPath(for: imagePath)
            return "![\(safeAlt)](\(linkPath)\(titleAttr))"
        }

        let alignStyle: String
        switch alignment {
        case .left:
            alignStyle = "float:left; margin-right:16px;"
        case .center:
            alignStyle = "display:block; margin:0 auto;"
        case .right:
            alignStyle = "float:right; margin-left:16px;"
        case .none:
            alignStyle = ""
        }

        let style = "width:\(widthPercent)%; \(alignStyle)".trimmingCharacters(in: .whitespaces)
        let titleHtml = title.isEmpty ? "" : " title=\"\(title.replacingOccurrences(of: "\"", with: "&quot;"))\""
        return "<img src=\"\(imagePath)\" alt=\"\(safeAlt)\"\(titleHtml) style=\"\(style)\">"
    }

    /// Wraps paths with spaces or non-ASCII in angle brackets for CommonMark.
    private static func markdownLinkPath(for path: String) -> String {
        if path.hasPrefix("<") && path.hasSuffix(">") { return path }
        let needsBrackets = path.contains(" ")
            || path.unicodeScalars.contains(where: { $0.value > 127 })
        return needsBrackets ? "<\(path)>" : path
    }

    static func beardyURL(forLocalPath path: String) -> String {
        let encoded = path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
            }
            .joined(separator: "/")
        if path.hasPrefix("/") {
            return "beardy://localhost/\(encoded.dropFirst())"
        }
        return "beardy://localhost/\(encoded)"
    }

    static func localPath(fromBeardyURL url: URL) -> String? {
        var path = url.path
        if path.isEmpty || path == "/" {
            let prefix = "beardy://localhost"
            guard let range = url.absoluteString.range(of: prefix) else { return nil }
            path = String(url.absoluteString[range.upperBound...])
        }
        guard !path.isEmpty else { return nil }
        if !path.hasPrefix("/") {
            path = "/" + path
        }
        return path.removingPercentEncoding ?? path
    }
}
