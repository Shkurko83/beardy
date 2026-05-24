//
//  ExportConverters.swift
//  Beardy2
//

import Foundation

enum ExportError: LocalizedError {
    case conversionFailed(String)
    case pandocNotInstalled
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .conversionFailed(let detail):
            return detail
        case .pandocNotInstalled:
            return "Pandoc is not installed. Install it with Homebrew (brew install pandoc) to export EPUB or LaTeX."
        case .unsupportedFormat:
            return "This export format is not supported."
        }
    }
}

enum TextUtilConverter {
    static func convert(html: String, to outputURL: URL, format: String) throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempHTML = tempDir.appendingPathComponent("beardy-export-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(at: tempHTML) }

        try html.write(to: tempHTML, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", format, tempHTML.path, "-output", outputURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ExportError.conversionFailed("textutil could not create a \(format.uppercased()) file.")
        }
    }
}

enum PandocConverter {
    static var executablePath: String? {
        let candidates = [
            "/opt/homebrew/bin/pandoc",
            "/usr/local/bin/pandoc",
            "/opt/local/bin/pandoc"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isAvailable: Bool { executablePath != nil }

    static func convert(markdown: String, to outputURL: URL, format: String) throws {
        guard let pandoc = executablePath else {
            throw ExportError.pandocNotInstalled
        }

        let tempDir = FileManager.default.temporaryDirectory
        let tempMD = tempDir.appendingPathComponent("beardy-export-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: tempMD) }

        try markdown.write(to: tempMD, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pandoc)
        process.arguments = [tempMD.path, "-o", outputURL.path, "-t", format]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ExportError.conversionFailed("Pandoc could not create the \(outputURL.pathExtension.uppercased()) file.")
        }
    }

    static func exportEPUB(markdown: String, to outputURL: URL) throws {
        guard let pandoc = executablePath else { throw ExportError.pandocNotInstalled }

        let tempDir = FileManager.default.temporaryDirectory
        let tempMD = tempDir.appendingPathComponent("beardy-export-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: tempMD) }

        try markdown.write(to: tempMD, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pandoc)
        process.arguments = [tempMD.path, "-o", outputURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ExportError.conversionFailed("Pandoc could not create the EPUB file.")
        }
    }
}
