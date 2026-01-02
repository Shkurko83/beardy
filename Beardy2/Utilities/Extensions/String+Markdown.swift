//
//  String+Markdown.swift
//  Beardy2
//
//  Created by Butt Simpson on 27.12.2025.
//

import Foundation

// MARK: - String Extensions for Markdown
extension String {
    
    // MARK: - Markdown Detection
    
    /// Check if string contains markdown syntax
    var containsMarkdown: Bool {
        return containsHeaders ||
               containsBold ||
               containsItalic ||
               containsCode ||
               containsLinks ||
               containsLists
    }
    
    /// Check if string contains markdown headers
    var containsHeaders: Bool {
        return range(of: "^#{1,6}\\s+", options: .regularExpression) != nil
    }
    
    /// Check if string contains bold text
    var containsBold: Bool {
        return contains("**") || contains("__")
    }
    
    /// Check if string contains italic text
    var containsItalic: Bool {
        return contains("*") || contains("_")
    }
    
    /// Check if string contains code blocks or inline code
    var containsCode: Bool {
        return contains("`")
    }
    
    /// Check if string contains links
    var containsLinks: Bool {
        return range(of: "\\[.*?\\]\\(.*?\\)", options: .regularExpression) != nil
    }
    
    /// Check if string contains lists
    var containsLists: Bool {
        return range(of: "^[\\s]*[-*+]\\s+", options: .regularExpression) != nil ||
               range(of: "^[\\s]*\\d+\\.\\s+", options: .regularExpression) != nil
    }
    
    // MARK: - Markdown Parsing
    
    /// Extract all markdown headers from string
    func extractHeaders() -> [(level: Int, text: String, range: Range<String.Index>)] {
        var headers: [(Int, String, Range<String.Index>)] = []
        let pattern = "^(#{1,6})\\s+(.+)$"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return headers
        }
        
        let nsString = self as NSString
        let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            if match.numberOfRanges == 3 {
                let hashesRange = match.range(at: 1)
                let textRange = match.range(at: 2)
                
                if let hashesSwiftRange = Range(hashesRange, in: self),
                   let textSwiftRange = Range(textRange, in: self) {
                    let level = String(self[hashesSwiftRange]).count
                    let text = String(self[textSwiftRange])
                    headers.append((level, text, textSwiftRange))
                }
            }
        }
        
        return headers
    }
    
    /// Extract all markdown links
    func extractLinks() -> [(text: String, url: String)] {
        var links: [(String, String)] = []
        let pattern = "\\[([^\\]]+)\\]\\(([^\\)]+)\\)"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return links
        }
        
        let nsString = self as NSString
        let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            if match.numberOfRanges == 3 {
                let textRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                
                if let textSwiftRange = Range(textRange, in: self),
                   let urlSwiftRange = Range(urlRange, in: self) {
                    let text = String(self[textSwiftRange])
                    let url = String(self[urlSwiftRange])
                    links.append((text, url))
                }
            }
        }
        
        return links
    }
    
    /// Extract all images
    func extractImages() -> [(alt: String, url: String)] {
        var images: [(String, String)] = []
        let pattern = "!\\[([^\\]]*)\\]\\(([^\\)]+)\\)"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return images
        }
        
        let nsString = self as NSString
        let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            if match.numberOfRanges == 3 {
                let altRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                
                if let altSwiftRange = Range(altRange, in: self),
                   let urlSwiftRange = Range(urlRange, in: self) {
                    let alt = String(self[altSwiftRange])
                    let url = String(self[urlSwiftRange])
                    images.append((alt, url))
                }
            }
        }
        
        return images
    }
    
    // MARK: - Markdown Formatting
    
    /// Wrap text with markdown bold syntax
    func wrapWithBold() -> String {
        return "**\(self)**"
    }
    
    /// Wrap text with markdown italic syntax
    func wrapWithItalic() -> String {
        return "*\(self)*"
    }
    
    /// Wrap text with markdown strikethrough syntax
    func wrapWithStrikethrough() -> String {
        return "~~\(self)~~"
    }
    
    /// Wrap text with markdown inline code syntax
    func wrapWithInlineCode() -> String {
        return "`\(self)`"
    }
    
    /// Create markdown link
    func toMarkdownLink(url: String) -> String {
        return "[\(self)](\(url))"
    }
    
    /// Create markdown image
    func toMarkdownImage(url: String) -> String {
        return "![\(self)](\(url))"
    }
    
    /// Add heading level
    func toMarkdownHeading(level: Int) -> String {
        let hashes = String(repeating: "#", count: min(max(level, 1), 6))
        return "\(hashes) \(self)"
    }
    
    // MARK: - Line Operations
    
    /// Get line at specific index
    func line(at index: Int) -> String? {
        let lines = self.components(separatedBy: .newlines)
        guard index >= 0 && index < lines.count else { return nil }
        return lines[index]
    }
    
    /// Get line number for character index
    func lineNumber(at characterIndex: Int) -> Int {
        guard characterIndex >= 0 && characterIndex <= count else { return 0 }
        
        let substring = String(prefix(characterIndex))
        return substring.components(separatedBy: .newlines).count - 1
    }
    
    /// Get character range for line number
    func rangeOfLine(at lineNumber: Int) -> Range<String.Index>? {
        let lines = components(separatedBy: .newlines)
        guard lineNumber >= 0 && lineNumber < lines.count else { return nil }
        
        var currentIndex = startIndex
        for i in 0..<lineNumber {
            guard let nextIndex = index(currentIndex, offsetBy: lines[i].count + 1, limitedBy: endIndex) else {
                return nil
            }
            currentIndex = nextIndex
        }
        
        let lineEnd = index(currentIndex, offsetBy: lines[lineNumber].count, limitedBy: endIndex) ?? endIndex
        return currentIndex..<lineEnd
    }
    
    /// Insert text at line
    mutating func insertAtLine(_ lineNumber: Int, text: String) {
        let lines = components(separatedBy: .newlines)
        guard lineNumber >= 0 && lineNumber <= lines.count else { return }
        
        var newLines = lines
        if lineNumber == lines.count {
            newLines.append(text)
        } else {
            newLines.insert(text, at: lineNumber)
        }
        
        self = newLines.joined(separator: "\n")
    }
    
    // MARK: - Statistics
    
    /// Count words in string
    var wordCount: Int {
        let words = components(separatedBy: .whitespacesAndNewlines)
        return words.filter { !$0.isEmpty }.count
    }
    
    /// Count characters (excluding whitespace)
    var characterCountWithoutSpaces: Int {
        return filter { !$0.isWhitespace }.count
    }
    
    /// Count lines
    var lineCount: Int {
        return components(separatedBy: .newlines).count
    }
    
    /// Count paragraphs
    var paragraphCount: Int {
        return components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
    
    /// Estimate reading time in minutes
    var readingTimeMinutes: Int {
        let wordsPerMinute = 200
        return max(1, wordCount / wordsPerMinute)
    }
    
    // MARK: - Cleaning
    
    /// Remove markdown syntax
    var withoutMarkdown: String {
        var text = self
        
        // Remove code blocks
        text = text.replacingOccurrences(of: "```[^`]*```", with: "", options: .regularExpression)
        
        // Remove inline code
        text = text.replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)
        
        // Remove images
        text = text.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^\\)]+\\)", with: "", options: .regularExpression)
        
        // Remove links but keep text
        text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        
        // Remove headers
        text = text.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: [.regularExpression])
        
        // Remove bold
        text = text.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
        
        // Remove italic
        text = text.replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "_([^_]+)_", with: "$1", options: .regularExpression)
        
        // Remove strikethrough
        text = text.replacingOccurrences(of: "~~([^~]+)~~", with: "$1", options: .regularExpression)
        
        // Remove blockquotes
//        text = text.replacingOccurrences(of: "^>\\s+", with: "", options: [.regularExpression, .anchorsMatchLines])
        text = text.replacingOccurrences(of: "^>\\s+", with: "", options: [.regularExpression])
        
        // Remove list markers
        text = text.replacingOccurrences(of: "^[\\s]*[-*+]\\s+", with: "", options: [.regularExpression])
        text = text.replacingOccurrences(of: "^[\\s]*\\d+\\.\\s+", with: "", options: [.regularExpression])
        
        // Remove horizontal rules
        text = text.replacingOccurrences(of: "^[-*_]{3,}$", with: "", options: [.regularExpression])
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Trim trailing whitespace from each line
    var trimmingTrailingWhitespace: String {
        return components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }
    
    // MARK: - Validation
    
    /// Check if string is valid markdown
    var isValidMarkdown: Bool {
        // Check for balanced code blocks
        let codeBlockCount = components(separatedBy: "```").count - 1
        guard codeBlockCount % 2 == 0 else { return false }
        
        // Check for balanced inline code
        let inlineCodeCount = components(separatedBy: "`").count - 1
        guard inlineCodeCount % 2 == 0 else { return false }
        
        return true
    }
    
    // MARK: - Search & Replace
    
    /// Find all occurrences of pattern
    func findOccurrences(of pattern: String, options: String.CompareOptions = []) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchRange = startIndex..<endIndex
        
        while let range = range(of: pattern, options: options, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<endIndex
        }
        
        return ranges
    }
    
    /// Count occurrences of substring
    func countOccurrences(of substring: String, options: String.CompareOptions = []) -> Int {
        return findOccurrences(of: substring, options: options).count
    }
    
    // MARK: - URL Handling
    
    /// Check if string is a valid URL
    var isValidURL: Bool {
        guard let url = URL(string: self) else { return false }
        return url.scheme != nil && url.host != nil
    }
    
    /// Extract all URLs from string
    var extractedURLs: [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        
        let matches = detector.matches(in: self, options: [], range: NSRange(location: 0, length: utf16.count))
        return matches.compactMap { match in
            guard let range = Range(match.range, in: self) else { return nil }
            return String(self[range])
        }
    }
}

// MARK: - NSRange Extensions
extension NSRange {
    /// Convert NSRange to Range<String.Index>
    func toRange(in string: String) -> Range<String.Index>? {
        guard let range = Range(self, in: string) else { return nil }
        return range
    }
}

// MARK: - Range Extensions
extension Range where Bound == String.Index {
    /// Convert Range<String.Index> to NSRange
    func toNSRange(in string: String) -> NSRange {
        return NSRange(self, in: string)
    }
}
