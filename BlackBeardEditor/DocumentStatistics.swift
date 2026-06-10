import Foundation
import SwiftUI

// MARK: - Document Statistics Model
struct DocumentStatistics {
    // Basic counts
    var wordCount: Int = 0
    var characterCount: Int = 0
    var characterCountNoSpaces: Int = 0
    var lineCount: Int = 0
    var paragraphCount: Int = 0
    
    // Reading time
    var readingTimeMinutes: Int = 0
    var readingTimeSeconds: Int = 0
    
    // Markdown specific
    var headingCount: Int = 0
    var linkCount: Int = 0
    var imageCount: Int = 0
    var codeBlockCount: Int = 0
    var listCount: Int = 0
    var tableCount: Int = 0
    var blockquoteCount: Int = 0
    
    // File info
    var fileSize: Int64 = 0
    var lastModified: Date?
    var created: Date?
    
    init() {}
    
    init(from content: String) {
        self.update(from: content)
    }
    
    mutating func update(from content: String) {
        // Basic counts using String+Markdown extensions
        self.wordCount = content.wordCount
        self.characterCount = content.count
        self.characterCountNoSpaces = content.characterCountWithoutSpaces
        self.lineCount = content.lineCount
        self.paragraphCount = content.paragraphCount
        
        // Reading time
        self.readingTimeMinutes = content.readingTimeMinutes
        self.readingTimeSeconds = (content.wordCount * 60) / 200 // 200 words per minute
        
        // Markdown elements
        self.headingCount = content.extractHeaders().count
        self.linkCount = content.extractLinks().count
        self.imageCount = content.extractImages().count
        self.codeBlockCount = content.countOccurrences(of: "```")
        self.listCount = countLists(in: content)
        self.tableCount = countTables(in: content)
        self.blockquoteCount = countBlockquotes(in: content)
    }
    
    // MARK: - Private Helpers
    
    private func countLists(in content: String) -> Int {
        let bulletLists = content.countOccurrences(of: "^[\\s]*[-*+]\\s+", options: .regularExpression)
        let orderedLists = content.countOccurrences(of: "^[\\s]*\\d+\\.\\s+", options: .regularExpression)
        return bulletLists + orderedLists
    }
    
    private func countTables(in content: String) -> Int {
        let lines = content.components(separatedBy: .newlines)
        var tableCount = 0
        var inTable = false
        
        for line in lines {
            if line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !inTable {
                    tableCount += 1
                    inTable = true
                }
            } else if inTable {
                inTable = false
            }
        }
        
        return tableCount
    }
    
    private func countBlockquotes(in content: String) -> Int {
        return content.countOccurrences(of: "^>\\s+", options: .regularExpression)
    }
    
    // MARK: - Formatted Strings
    
    var formattedWordCount: String {
        return formatNumber(wordCount)
    }
    
    var formattedCharacterCount: String {
        return formatNumber(characterCount)
    }
    
    var formattedReadingTime: String {
        if readingTimeMinutes < 1 {
            return "< 1 min"
        } else if readingTimeMinutes == 1 {
            return "1 min"
        } else {
            return "\(readingTimeMinutes) mins"
        }
    }
    
    var formattedFileSize: String {
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - Document Statistics View
struct DocumentStatisticsView: View {
    let statistics: DocumentStatistics
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Compact view
            HStack(spacing: 16) {
                StatItem(
                    icon: "text.alignleft",
                    value: statistics.formattedWordCount,
                    label: "words"
                )
                
                StatItem(
                    icon: "character",
                    value: statistics.formattedCharacterCount,
                    label: "chars"
                )
                
                StatItem(
                    icon: "clock",
                    value: statistics.formattedReadingTime,
                    label: "read"
                )
                
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            
            // Expanded view
            if isExpanded {
                Divider()
                    .padding(.vertical, 4)
                
                VStack(spacing: 8) {
                    StatSection(title: "Content") {
                        StatRow(label: "Words", value: statistics.formattedWordCount)
                        StatRow(label: "Characters", value: statistics.formattedCharacterCount)
                        StatRow(label: "Characters (no spaces)", value: "\(statistics.characterCountNoSpaces)")
                        StatRow(label: "Lines", value: "\(statistics.lineCount)")
                        StatRow(label: "Paragraphs", value: "\(statistics.paragraphCount)")
                    }
                    
                    if statistics.hasMarkdownElements {
                        StatSection(title: "Markdown Elements") {
                            if statistics.headingCount > 0 {
                                StatRow(label: "Headings", value: "\(statistics.headingCount)")
                            }
                            if statistics.linkCount > 0 {
                                StatRow(label: "Links", value: "\(statistics.linkCount)")
                            }
                            if statistics.imageCount > 0 {
                                StatRow(label: "Images", value: "\(statistics.imageCount)")
                            }
                            if statistics.codeBlockCount > 0 {
                                StatRow(label: "Code Blocks", value: "\(statistics.codeBlockCount / 2)")
                            }
                            if statistics.listCount > 0 {
                                StatRow(label: "List Items", value: "\(statistics.listCount)")
                            }
                            if statistics.tableCount > 0 {
                                StatRow(label: "Tables", value: "\(statistics.tableCount)")
                            }
                            if statistics.blockquoteCount > 0 {
                                StatRow(label: "Blockquotes", value: "\(statistics.blockquoteCount)")
                            }
                        }
                    }
                    
                    StatSection(title: "Reading Time") {
                        StatRow(label: "Estimated", value: statistics.formattedReadingTime)
                        StatRow(label: "At 200 WPM", value: statistics.formattedReadingTime)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Stat Item (Compact)
struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
            
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Stat Section
struct StatSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            VStack(spacing: 4) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Stat Row
struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Extensions
extension DocumentStatistics {
    var hasMarkdownElements: Bool {
        return headingCount > 0 ||
               linkCount > 0 ||
               imageCount > 0 ||
               codeBlockCount > 0 ||
               listCount > 0 ||
               tableCount > 0 ||
               blockquoteCount > 0
    }
}

// MARK: - Live Statistics View (for toolbar)
struct LiveStatisticsView: View {
    @EnvironmentObject var documentManager: DocumentManager
    
    var statistics: DocumentStatistics {
        if let doc = documentManager.currentDocument {
            return DocumentStatistics(from: doc.content)
        }
        return DocumentStatistics()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 10))
                Text("\(statistics.wordCount) words")
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                Image(systemName: "character")
                    .font(.system(size: 10))
                Text("\(statistics.characterCount) chars")
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(statistics.formattedReadingTime)
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

// MARK: - Full Statistics Panel
struct FullStatisticsPanel: View {
    let statistics: DocumentStatistics
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Document Statistics")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    ExpandedStatisticsContent(statistics: statistics)
                        .padding()
                }
            }
        }
        .frame(width: 350, height: 500)
    }
}

// MARK: - Expanded Statistics Content
struct ExpandedStatisticsContent: View {
    let statistics: DocumentStatistics
    
    var body: some View {
        VStack(spacing: 12) {
            StatSection(title: "Content") {
                StatRow(label: "Words", value: statistics.formattedWordCount)
                StatRow(label: "Characters", value: statistics.formattedCharacterCount)
                StatRow(label: "Characters (no spaces)", value: "\(statistics.characterCountNoSpaces)")
                StatRow(label: "Lines", value: "\(statistics.lineCount)")
                StatRow(label: "Paragraphs", value: "\(statistics.paragraphCount)")
            }
            
            if statistics.hasMarkdownElements {
                StatSection(title: "Markdown Elements") {
                    if statistics.headingCount > 0 {
                        StatRow(label: "Headings", value: "\(statistics.headingCount)")
                    }
                    if statistics.linkCount > 0 {
                        StatRow(label: "Links", value: "\(statistics.linkCount)")
                    }
                    if statistics.imageCount > 0 {
                        StatRow(label: "Images", value: "\(statistics.imageCount)")
                    }
                    if statistics.codeBlockCount > 0 {
                        StatRow(label: "Code Blocks", value: "\(statistics.codeBlockCount / 2)")
                    }
                    if statistics.listCount > 0 {
                        StatRow(label: "List Items", value: "\(statistics.listCount)")
                    }
                    if statistics.tableCount > 0 {
                        StatRow(label: "Tables", value: "\(statistics.tableCount)")
                    }
                    if statistics.blockquoteCount > 0 {
                        StatRow(label: "Blockquotes", value: "\(statistics.blockquoteCount)")
                    }
                }
            }
            
            StatSection(title: "Reading Time") {
                StatRow(label: "Estimated", value: statistics.formattedReadingTime)
                StatRow(label: "At 200 WPM", value: statistics.formattedReadingTime)
            }
        }
    }
}

struct DocumentStatistics_Previews: PreviewProvider {
    static var previews: some View {
        let sampleContent = """
        # Sample Document
        
        This is a **sample** markdown document with some *italic* text.
        
        ## Links and Images
        
        Here's a [link](https://example.com) and an image:
        ![Alt text](image.png)
        
        ## Code
        
        Inline `code` and:
        
        ```swift
        let code = "block"
        ```
        
        ## Lists
        
        - Item 1
        - Item 2
        - Item 3
        
        > This is a blockquote
        """
        
        let stats = DocumentStatistics(from: sampleContent)
        
        return VStack(spacing: 20) {
            DocumentStatisticsView(statistics: stats)
            LiveStatisticsView()
                .environmentObject(DocumentManager())
        }
        .padding()
        .frame(width: 400)
    }
}
