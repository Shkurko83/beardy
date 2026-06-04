import Foundation

enum DiffEngine {

    private static let blockChangeThreshold: Double = 0.4
    /// Block mode uses a slightly lower bar than word mode (more paragraph-level groups).
    private static let blockModeThreshold: Double = 0.32

    static func compute(
        current: String,
        comparison: String,
        granularity: DiffGranularity,
        documentURL: URL? = nil
    ) -> [DiffChunk] {
        StructuredDiffEngine.compute(
            current: current,
            comparison: comparison,
            granularity: granularity,
            documentURL: documentURL
        )
    }

    private static func appendParagraphChange(
        oldText: String,
        newText: String,
        granularity: DiffGranularity,
        chunks: inout [DiffChunk],
        changeIndex: inout Int
    ) {
        let ratio = levenshteinRatio(oldText, newText)
        let threshold = granularity == .block ? blockModeThreshold : blockChangeThreshold
        let useBlock = ratio > threshold
            || isStructuralBlock(oldText)
            || isStructuralBlock(newText)
            || containsRichMarkdown(oldText)
            || containsRichMarkdown(newText)

        if useBlock {
            changeIndex += 1
            chunks.append(DiffChunk(
                kind: .blockDeleted,
                text: oldText,
                renderedHTML: nil,
                changeIndex: changeIndex,
                blockOrdinal: nil
            ))
            changeIndex += 1
            chunks.append(DiffChunk(
                kind: .blockInserted,
                text: newText,
                renderedHTML: nil,
                changeIndex: changeIndex,
                blockOrdinal: nil
            ))
            return
        }

        appendWordLevelChange(
            oldText: oldText,
            newText: newText,
            chunks: &chunks,
            changeIndex: &changeIndex
        )
    }

    private static func appendWordLevelChange(
        oldText: String,
        newText: String,
        chunks: inout [DiffChunk],
        changeIndex: inout Int
    ) {
        let oldWords = tokenizeWords(oldText)
        let newWords = tokenizeWords(newText)
        let wordOps = myersDiff(old: oldWords, new: newWords)

        for op in wordOps {
            switch op.op {
            case .equal:
                let joined = joinWords(op.value)
                if !joined.isEmpty {
                    chunks.append(DiffChunk(kind: .equal, text: joined, renderedHTML: nil, changeIndex: nil, blockOrdinal: nil))
                }
            case .delete:
                changeIndex += 1
                chunks.append(DiffChunk(
                    kind: .deleted,
                    text: joinWords(op.value),
                    renderedHTML: nil,
                    changeIndex: changeIndex,
                    blockOrdinal: nil
                ))
            case .insert:
                changeIndex += 1
                chunks.append(DiffChunk(
                    kind: .inserted,
                    text: joinWords(op.value),
                    renderedHTML: nil,
                    changeIndex: changeIndex,
                    blockOrdinal: nil
                ))
            }
        }
    }

    // MARK: - Paragraph splitting (group tables, code, blockquotes)

    static func splitParagraphs(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var blocks: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if line.hasPrefix("```") {
                var chunk = [line]
                index += 1
                while index < lines.count {
                    chunk.append(lines[index])
                    if lines[index].hasPrefix("```") {
                        index += 1
                        break
                    }
                    index += 1
                }
                blocks.append(chunk.joined(separator: "\n"))
                continue
            }

            if isTableLine(line) {
                var chunk: [String] = []
                while index < lines.count, isTableLine(lines[index]) {
                    chunk.append(lines[index])
                    index += 1
                }
                blocks.append(chunk.joined(separator: "\n"))
                continue
            }

            if line.hasPrefix(">") {
                var chunk: [String] = []
                while index < lines.count, lines[index].hasPrefix(">") {
                    chunk.append(lines[index])
                    index += 1
                }
                blocks.append(chunk.joined(separator: "\n"))
                continue
            }

            if isListLine(line) {
                var chunk: [String] = []
                while index < lines.count, isListLine(lines[index]) {
                    chunk.append(lines[index])
                    index += 1
                }
                blocks.append(chunk.joined(separator: "\n"))
                continue
            }

            if index + 1 < lines.count, lines[index + 1].trimmingCharacters(in: .whitespaces).isEmpty {
                blocks.append(line)
                index += 2
                continue
            }

            blocks.append(line)
            index += 1
        }

        return blocks
    }

    private static func joinBlocks(_ blocks: [String]) -> String {
        blocks.joined(separator: "\n\n")
    }

    private static func isTableLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("|") else { return false }
        let stripped = t
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty { return true }
        return stripped.contains(where: \.isLetter)
    }

    private static func isListLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("- ")
            || t.hasPrefix("* ")
            || t.hasPrefix("+ ")
            || t.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
            || t.hasPrefix("- [")
    }

    static func isStructuralBlock(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") { return true }
        if t.contains("\n") {
            let lines = t.components(separatedBy: "\n")
            if lines.allSatisfy(isTableLine) { return true }
            if lines.allSatisfy({ $0.hasPrefix(">") }) { return true }
            if lines.allSatisfy(isListLine) { return true }
        }
        return isTableLine(t) || t.hasPrefix(">") || isListLine(t)
    }

    /// Links, emphasis, headings — word-level raw spans break rendering.
    static func containsRichMarkdown(_ text: String) -> Bool {
        if text.contains("[") && text.contains("](") { return true }
        if text.contains("**") || text.contains("__") { return true }
        if text.contains("*") || text.contains("_") { return true }
        if text.contains("`") { return true }
        if text.range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func tokenizeWords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func joinWords(_ words: [String]) -> String {
        words.joined(separator: " ")
    }

    static func levenshteinRatio(_ a: String, _ b: String) -> Double {
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 0 }
        return Double(levenshtein(a, b)) / Double(maxLen)
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }

    // MARK: - LCS diff

    private enum DiffOpKind {
        case equal, delete, insert
    }

    private struct DiffOp {
        let op: DiffOpKind
        let value: [String]
    }

    private static func myersDiff(old: [String], new: [String]) -> [DiffOp] {
        if old.isEmpty {
            return new.isEmpty ? [] : [DiffOp(op: .insert, value: new)]
        }
        if new.isEmpty {
            return [DiffOp(op: .delete, value: old)]
        }

        let n = old.count
        let m = new.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if old[i - 1] == new[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var ops: [DiffOp] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, old[i - 1] == new[j - 1] {
                ops.append(DiffOp(op: .equal, value: [old[i - 1]]))
                i -= 1
                j -= 1
            } else if j > 0, (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                ops.append(DiffOp(op: .insert, value: [new[j - 1]]))
                j -= 1
            } else {
                ops.append(DiffOp(op: .delete, value: [old[i - 1]]))
                i -= 1
            }
        }

        return ops.reversed().reduce(into: [DiffOp]()) { result, op in
            if let last = result.last, last.op == op.op {
                result[result.count - 1] = DiffOp(op: op.op, value: last.value + op.value)
            } else {
                result.append(op)
            }
        }
    }
}
