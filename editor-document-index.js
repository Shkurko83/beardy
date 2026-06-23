/**
 * Unified document structure index: blocks, headings, line→block map, preview layout estimates.
 * Single source of truth for outline, virtual preview, and split scroll anchoring.
 */
(function documentIndexModule(global) {
    'use strict';

    const DEFAULT_DEBOUNCE_MS = 400;

    let hooks = {
        normalizeImages: (text) => text || '',
        extractReferences: () => ({ text: '', refs: {}, footnotes: {}, lineMap: null }),
        parseBlocks: () => [],
        coalesceHTMLBlocks: (blocks) => blocks,
        contentKey: (text) => String(text?.length ?? 0),
        lineHeightPx: () => 22.4,
    };

    let debounceMs = DEFAULT_DEBOUNCE_MS;
    let rebuildTimer = 0;

    const state = {
        key: '',
        normalizedText: '',
        normalizedLength: 0,
        blocks: [],
        bodyText: '',
        footnotes: null,
        refs: null,
        headings: [],
        lineToBlock: [],
        lineCount: 1,
        layout: [],
    };

    function estimateBlockHeight(block, lh) {
        const src = block?.source || '';
        const lines = src ? src.split('\n').length : 1;
        switch (block?.type) {
            case 'empty': return lh * 1.2;
            case 'hr': return lh * 0.75;
            case 'h1': return lh * 2.6;
            case 'h2': return lh * 2.2;
            case 'h3': return lh * 1.9;
            case 'h4':
            case 'h5':
            case 'h6': return lh * 1.55;
            case 'code-fence': return Math.max(lh * 2.2, lines * lh * 1.12 + lh);
            case 'table': return Math.max(lh * 3, lines * lh * 1.15);
            case 'list': return Math.max(lh * 1.4, lines * lh * 1.3);
            case 'math': return lh * 3.2;
            case 'mermaid': return lh * 9;
            default: return Math.max(lh * 1.5, lines * lh * 1.5);
        }
    }

    function headingLevelFromType(type) {
        const match = /^h([1-6])$/.exec(type || '');
        return match ? Number(match[1]) : 0;
    }

    function headingTitleFromSource(source) {
        const line = (source || '').split('\n')[0] || '';
        const match = line.match(/^#{1,6}\s+(.+)/);
        return match ? match[1].trim() : line.trim();
    }

    function buildHeadings(blocks) {
        const headings = [];
        for (const block of blocks) {
            const level = headingLevelFromType(block.type);
            if (!level) continue;
            const title = headingTitleFromSource(block.source);
            if (!title) continue;
            headings.push({
                lineNumber: Number.isFinite(block.sourceLine) ? block.sourceLine : 0,
                level,
                title,
            });
        }
        return headings;
    }

    function buildLineToBlock(blocks, lineCount) {
        const map = new Int32Array(Math.max(1, lineCount));
        map.fill(-1);
        blocks.forEach((block, blockIndex) => {
            const start = Number.isFinite(block.sourceLine) ? block.sourceLine : 0;
            const span = Math.max(1, (block.source || '').split('\n').length);
            for (let line = start; line < start + span && line < map.length; line++) {
                map[line] = blockIndex;
            }
        });
        for (let i = 0; i < map.length; i++) {
            if (map[i] < 0) map[i] = i > 0 ? map[i - 1] : 0;
        }
        return map;
    }

    function buildLayoutEstimates(blocks) {
        const lh = hooks.lineHeightPx();
        let top = 0;
        return blocks.map((block, index) => {
            const height = estimateBlockHeight(block, lh);
            const entry = {
                index,
                line: Number.isFinite(block.sourceLine) ? block.sourceLine : 0,
                top,
                height,
                measured: false,
            };
            top += height;
            return entry;
        });
    }

    function rebuild(text) {
        const normalized = hooks.normalizeImages(text || '');
        const key = hooks.contentKey(normalized);
        if (key === state.key && state.blocks.length) {
            return getSnapshot();
        }

        const extracted = hooks.extractReferences(normalized);
        let blocks = hooks.parseBlocks(extracted.text || '', extracted.lineMap);
        blocks = hooks.coalesceHTMLBlocks(blocks);

        const lineCount = normalized ? normalized.split('\n').length : 1;

        state.key = key;
        state.normalizedText = normalized;
        state.normalizedLength = normalized.length;
        state.blocks = blocks;
        state.bodyText = extracted.text || '';
        state.footnotes = extracted.footnotes ?? null;
        state.refs = extracted.refs ?? null;
        state.headings = buildHeadings(blocks);
        state.lineCount = lineCount;
        state.lineToBlock = buildLineToBlock(blocks, lineCount);
        state.layout = buildLayoutEstimates(blocks);

        return getSnapshot();
    }

    function invalidate() {
        state.key = '';
    }

    function isReadyFor(text) {
        const normalized = hooks.normalizeImages(text || '');
        return state.key === hooks.contentKey(normalized) && state.blocks.length > 0;
    }

    function ensure(text) {
        const normalized = hooks.normalizeImages(text || '');
        const key = hooks.contentKey(normalized);
        if (key === state.key && state.blocks.length) return getSnapshot();
        return rebuild(text);
    }

    function scheduleRebuild(text) {
        clearTimeout(rebuildTimer);
        rebuildTimer = setTimeout(() => {
            rebuildTimer = 0;
            rebuild(text);
        }, debounceMs);
    }

    function cancelScheduledRebuild() {
        clearTimeout(rebuildTimer);
        rebuildTimer = 0;
    }

    function getSnapshot() {
        return {
            key: state.key,
            normalizedText: state.normalizedText,
            normalizedLength: state.normalizedLength,
            bodyText: state.bodyText,
            blocks: state.blocks,
            footnotes: state.footnotes,
            refs: state.refs,
            headings: state.headings,
            lineCount: state.lineCount,
            lineToBlock: state.lineToBlock,
            layout: state.layout,
        };
    }

    function getBlocks() {
        return state.blocks;
    }

    function getHeadings() {
        return state.headings;
    }

    function getLayout() {
        return state.layout;
    }

    function getBlockLineAnchors() {
        return state.layout.map((entry) => ({
            line: entry.line,
            top: entry.top,
            index: entry.index,
        }));
    }

    function findBlockIndexForSourceLine(line) {
        const layout = state.layout;
        if (!layout.length) return 0;
        let lo = 0;
        let hi = layout.length - 1;
        let result = 0;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (layout[mid].line <= line) {
                result = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return result;
    }

    function getPreviewYForSourceLine(line, subLinePx) {
        const layout = state.layout;
        if (!layout.length) return 0;
        let seg = layout[0];
        for (let i = 0; i < layout.length; i++) {
            if (layout[i].line <= line) seg = layout[i];
            else break;
        }
        const nextIdx = seg.index + 1;
        const next = layout[nextIdx];
        const lineSpan = next && next.line > seg.line ? next.line - seg.line : 8;
        const lh = hooks.lineHeightPx();
        const frac = Math.max(0, Math.min(1, (line - seg.line + (subLinePx || 0) / lh) / lineSpan));
        const segHeight = next
            ? Math.max(seg.height, next.top - seg.top)
            : seg.height;
        return seg.top + frac * segHeight;
    }

    function getSourceLineForPreviewY(y) {
        const layout = state.layout;
        if (!layout.length) return 0;
        let lo = 0;
        let hi = layout.length - 1;
        if (y <= layout[0].top) return layout[0].line;
        const last = layout.length - 1;
        if (y >= layout[last].top) return layout[last].line;
        while (lo < hi - 1) {
            const mid = (lo + hi) >> 1;
            if (layout[mid].top <= y) lo = mid;
            else hi = mid;
        }
        const seg = layout[lo];
        const next = layout[lo + 1];
        const segHeight = next ? Math.max(seg.height, next.top - seg.top) : seg.height;
        const offset = Math.max(0, y - seg.top);
        const frac = segHeight > 0 ? Math.min(1, offset / segHeight) : 0;
        const lineSpan = next && next.line > seg.line ? next.line - seg.line : 8;
        return Math.max(0, seg.line + frac * lineSpan);
    }

    function applyMeasuredLayout(measuredLayout) {
        if (!Array.isArray(measuredLayout) || !measuredLayout.length) return;
        if (measuredLayout.length !== state.layout.length) return;
        for (let i = 0; i < measuredLayout.length; i++) {
            const src = measuredLayout[i];
            const dst = state.layout[i];
            if (!dst || !src) continue;
            if (Number.isFinite(src.top)) dst.top = src.top;
            if (Number.isFinite(src.height) && src.height > 0) {
                dst.height = src.height;
                dst.measured = true;
            }
            if (Number.isFinite(src.line)) dst.line = src.line;
        }
    }

    function configure(next) {
        hooks = { ...hooks, ...(next || {}) };
        if (Number.isFinite(next?.debounceMs)) {
            debounceMs = next.debounceMs;
        }
    }

    global.documentIndex = {
        configure,
        rebuild,
        ensure,
        invalidate,
        isReadyFor,
        scheduleRebuild,
        cancelScheduledRebuild,
        getSnapshot,
        getBlocks,
        getHeadings,
        getLayout,
        getBlockLineAnchors,
        findBlockIndexForSourceLine,
        getPreviewYForSourceLine,
        getSourceLineForPreviewY,
        applyMeasuredLayout,
        getKey: () => state.key,
    };
})(window);
