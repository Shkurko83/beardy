import Foundation

/// Markdown-aware diff: renders all block types, word-level text, table cell diffs when shape matches.
enum StructuredDiffEngine {

    /// - Parameters:
    ///   - current: Text in the editor (the new version).
    ///   - comparison: Baseline to compare against (snapshot, external file, etc.).
    ///   Red / deleted = removed since `comparison`; green / inserted = added in `current`.
    static func compute(
        current: String,
        comparison: String,
        granularity: DiffGranularity,
        documentURL: URL? = nil
    ) -> [DiffChunk] {
        let oldBlocks = MarkdownBlockExtractor.extract(from: comparison)
        let newBlocks = MarkdownBlockExtractor.extract(from: current)
        let ops = BlockDiffLCS.diff(
            old: oldBlocks.map(\.fingerprint),
            new: newBlocks.map(\.fingerprint)
        )

        var chunks: [DiffChunk] = []
        var changeIndex = 0
        var oldIndex = 0
        var newIndex = 0
        var opIndex = 0

        while opIndex < ops.count {
            switch ops[opIndex] {
            case .equal(let count):
                for _ in 0..<count {
                    guard oldIndex < oldBlocks.count, newIndex < newBlocks.count else { break }
                    let oldBlock = oldBlocks[oldIndex]
                    let newBlock = newBlocks[newIndex]
                    if oldBlock.source != newBlock.source {
                        appendPair(
                            oldBlock: oldBlock,
                            newBlock: newBlock,
                            blockOrdinal: oldIndex,
                            granularity: granularity,
                            documentURL: documentURL,
                            chunks: &chunks,
                            changeIndex: &changeIndex
                        )
                    } else {
                        chunks.append(equalChunk(newBlock, blockOrdinal: oldIndex, documentURL: documentURL))
                    }
                    oldIndex += 1
                    newIndex += 1
                }
                opIndex += 1

            case .delete(let delCount):
                if opIndex + 1 < ops.count, case .insert(let insCount) = ops[opIndex + 1] {
                    let paired = min(delCount, insCount)
                    for offset in 0..<paired {
                        guard oldIndex + offset < oldBlocks.count,
                              newIndex + offset < newBlocks.count else { break }
                        appendPair(
                            oldBlock: oldBlocks[oldIndex + offset],
                            newBlock: newBlocks[newIndex + offset],
                            blockOrdinal: oldIndex + offset,
                            granularity: granularity,
                            documentURL: documentURL,
                            chunks: &chunks,
                            changeIndex: &changeIndex
                        )
                    }
                    oldIndex += paired
                    newIndex += paired

                    for _ in paired..<delCount {
                        guard oldIndex < oldBlocks.count else { break }
                        changeIndex += 1
                        chunks.append(blockChunk(
                            kind: .blockDeleted,
                            block: oldBlocks[oldIndex],
                            blockOrdinal: oldIndex,
                            changeIndex: changeIndex,
                            documentURL: documentURL
                        ))
                        oldIndex += 1
                    }
                    for _ in paired..<insCount {
                        guard newIndex < newBlocks.count else { break }
                        changeIndex += 1
                        chunks.append(blockChunk(
                            kind: .blockInserted,
                            block: newBlocks[newIndex],
                            blockOrdinal: newIndex,
                            changeIndex: changeIndex,
                            documentURL: documentURL
                        ))
                        newIndex += 1
                    }
                    opIndex += 2
                } else {
                    for _ in 0..<delCount {
                        guard oldIndex < oldBlocks.count else { break }
                        changeIndex += 1
                        chunks.append(blockChunk(
                            kind: .blockDeleted,
                            block: oldBlocks[oldIndex],
                            blockOrdinal: oldIndex,
                            changeIndex: changeIndex,
                            documentURL: documentURL
                        ))
                        oldIndex += 1
                    }
                    opIndex += 1
                }

            case .insert(let count):
                for _ in 0..<count {
                    guard newIndex < newBlocks.count else { break }
                    changeIndex += 1
                    chunks.append(blockChunk(
                        kind: .blockInserted,
                        block: newBlocks[newIndex],
                        blockOrdinal: newIndex,
                        changeIndex: changeIndex,
                        documentURL: documentURL
                    ))
                    newIndex += 1
                }
                opIndex += 1
            }
        }

        return chunks
    }

    // MARK: - Pair handling

    private static func appendPair(
        oldBlock: MarkdownBlock,
        newBlock: MarkdownBlock,
        blockOrdinal: Int,
        granularity: DiffGranularity,
        documentURL: URL?,
        chunks: inout [DiffChunk],
        changeIndex: inout Int
    ) {
        if oldBlock.source == newBlock.source {
            chunks.append(equalChunk(newBlock, blockOrdinal: blockOrdinal, documentURL: documentURL))
            return
        }

        if oldBlock.kind == .mathDisplay, newBlock.kind == .mathDisplay,
           MathBlockNormalizer.equivalentDisplayMath(oldBlock.source, newBlock.source) {
            chunks.append(equalChunk(newBlock, blockOrdinal: blockOrdinal, documentURL: documentURL))
            return
        }

        if let tableDiff = tryTableCellDiff(
            oldBlock: oldBlock,
            newBlock: newBlock,
            granularity: granularity,
            documentURL: documentURL,
            changeIndex: &changeIndex
        ) {
            if let first = tableDiff.firstChangeIndex {
                chunks.append(DiffChunk(
                    kind: .equal,
                    text: newBlock.source,
                    renderedHTML: tableDiff.html,
                    changeIndex: first,
                    blockOrdinal: blockOrdinal
                ))
                changeIndex = tableDiff.lastChangeIndex
            } else {
                chunks.append(DiffChunk(
                    kind: .equal,
                    text: newBlock.source,
                    renderedHTML: tableDiff.html,
                    changeIndex: nil,
                    blockOrdinal: blockOrdinal
                ))
            }
            return
        }

        if shouldUseBlockPair(
            oldBlock: oldBlock,
            newBlock: newBlock,
            granularity: granularity
        ) {
            changeIndex += 1
            let idx = changeIndex
            chunks.append(blockChunk(
                kind: .blockDeleted,
                block: oldBlock,
                blockOrdinal: blockOrdinal,
                changeIndex: idx,
                documentURL: documentURL
            ))
            chunks.append(blockChunk(
                kind: .blockInserted,
                block: newBlock,
                blockOrdinal: blockOrdinal,
                changeIndex: idx,
                documentURL: documentURL
            ))
            return
        }

        changeIndex += 1
        let html = renderTextualInlineDiff(
            oldBlock: oldBlock,
            newBlock: newBlock,
            highlightChangeIndex: changeIndex,
            documentURL: documentURL
        )
        chunks.append(DiffChunk(
            kind: .equal,
            text: newBlock.source,
            renderedHTML: html,
            changeIndex: changeIndex,
            blockOrdinal: blockOrdinal
        ))
    }

    private struct TableDiffResult {
        let html: String
        let firstChangeIndex: Int?
        let lastChangeIndex: Int
    }

    private static func tryTableCellDiff(
        oldBlock: MarkdownBlock,
        newBlock: MarkdownBlock,
        granularity: DiffGranularity,
        documentURL: URL?,
        changeIndex: inout Int
    ) -> TableDiffResult? {
        guard granularity == .word else { return nil }
        guard oldBlock.kind == .table, newBlock.kind == .table,
              let oldModel = TableModel.parse(source: oldBlock.source),
              let newModel = TableModel.parse(source: newBlock.source),
              oldModel.hasSameShape(as: newModel) else {
            return nil
        }

        var runningIndex = changeIndex
        let (html, firstIdx) = DiffMarkupRenderer.renderTableCellDiff(
            oldModel: oldModel,
            newModel: newModel,
            documentURL: documentURL,
            changeIndex: &runningIndex
        )
        let lastIdx = runningIndex
        return TableDiffResult(
            html: html,
            firstChangeIndex: firstIdx,
            lastChangeIndex: lastIdx
        )
    }

    /// Block mode: red/green pairs for every change. Word mode: prose/lists → inline; tables/code/images → blocks.
    private static func shouldUseBlockPair(
        oldBlock: MarkdownBlock,
        newBlock: MarkdownBlock,
        granularity: DiffGranularity
    ) -> Bool {
        if granularity == .block { return true }
        guard oldBlock.kind == newBlock.kind else { return true }
        return !oldBlock.isTextual || !newBlock.isTextual
    }

    private static func renderTextualInlineDiff(
        oldBlock: MarkdownBlock,
        newBlock: MarkdownBlock,
        highlightChangeIndex: Int,
        documentURL: URL?
    ) -> String {
        if newBlock.kind == .blockquote {
            return DiffMarkupRenderer.renderBlockquoteWordDiff(
                oldMarkdown: oldBlock.source,
                newMarkdown: newBlock.source,
                documentURL: documentURL
            )
        }

        if newBlock.kind == .list {
            return DiffMarkupRenderer.renderListWordDiff(
                oldMarkdown: oldBlock.source,
                newMarkdown: newBlock.source,
                documentURL: documentURL
            )
        }

        if DiffEngine.containsRichMarkdown(newBlock.source)
            || DiffEngine.containsRichMarkdown(oldBlock.source) {
            return DiffMarkupRenderer.renderInlineRichWordDiff(
                oldMarkdown: oldBlock.source,
                newMarkdown: newBlock.source,
                highlightChangeIndex: nil,
                documentURL: documentURL
            )
        }

        let inline = DiffMarkupRenderer.renderInlineWordDiff(
            oldText: oldBlock.plainText,
            newText: newBlock.plainText,
            highlightChangeIndex: nil,
            documentURL: documentURL
        )

        switch newBlock.kind {
        case .heading(let level):
            return "<h\(level) class=\"diff-inline-text\">\(inline)</h\(level)>\n"
        default:
            return "<p class=\"diff-inline-text\">\(inline)</p>\n"
        }
    }

    private static func equalChunk(
        _ block: MarkdownBlock,
        blockOrdinal: Int,
        documentURL: URL?
    ) -> DiffChunk {
        DiffChunk(
            kind: .equal,
            text: block.source,
            renderedHTML: DiffMarkupRenderer.renderBlock(block.source, documentURL: documentURL),
            changeIndex: nil,
            blockOrdinal: blockOrdinal
        )
    }

    private static func blockChunk(
        kind: DiffChunk.Kind,
        block: MarkdownBlock,
        blockOrdinal: Int,
        changeIndex: Int,
        documentURL: URL?
    ) -> DiffChunk {
        let html = DiffMarkupRenderer.renderBlock(block.source, documentURL: documentURL)
        return DiffChunk(
            kind: kind,
            text: block.source,
            renderedHTML: html,
            changeIndex: changeIndex,
            blockOrdinal: blockOrdinal
        )
    }
}
