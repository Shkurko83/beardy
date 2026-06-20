/**
 * Virtual preview: mount only visible blocks + spacers.
 * Used for large read-only preview / split panes (offline, main-thread friendly).
 */
(function virtualPreviewModule(global) {
    'use strict';

    const DEFAULTS = {
        blockThreshold: 320,
        charThreshold: 100000,
        windowSize: 72,
        buffer: 20,
        sourceLineBuffer: 48,
        measureWhileScrolling: false,
    };

    let hooks = {};
    let cfg = { ...DEFAULTS };

    const state = {
        active: false,
        blocks: [],
        layout: [],
        footnotes: null,
        readOnly: true,
        container: null,
        topSpacer: null,
        windowEl: null,
        bottomSpacer: null,
        mounted: new Map(),
        scrollRaf: 0,
        scrollIdleTimer: 0,
        isScrolling: false,
        pendingMeasure: new Set(),
    };

    function lineHeightPx() {
        const root = global.getComputedStyle?.(document.documentElement);
        const parsed = parseFloat(root?.getPropertyValue('--editor-line-height') || '');
        return Number.isFinite(parsed) && parsed > 0 ? parsed : 22.4;
    }

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

    function buildLayout(blocks) {
        const lh = lineHeightPx();
        let top = 0;
        state.layout = blocks.map((block, index) => {
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
        return state.layout;
    }

    function rebuildLayoutFrom(startIndex) {
        const lh = lineHeightPx();
        let top = startIndex > 0
            ? state.layout[startIndex - 1].top + state.layout[startIndex - 1].height
            : 0;
        for (let i = startIndex; i < state.blocks.length; i++) {
            const block = state.blocks[i];
            if (!state.layout[i]) {
                state.layout[i] = {
                    index: i,
                    line: Number.isFinite(block.sourceLine) ? block.sourceLine : 0,
                    top,
                    height: estimateBlockHeight(block, lh),
                    measured: false,
                };
            } else {
                if (!state.layout[i].measured) {
                    state.layout[i].height = estimateBlockHeight(block, lh);
                }
                state.layout[i].top = top;
                state.layout[i].line = Number.isFinite(block.sourceLine) ? block.sourceLine : 0;
                state.layout[i].index = i;
            }
            top += state.layout[i].height;
        }
        state.layout.length = state.blocks.length;
    }

    function applyHeightDelta(fromIndex, delta) {
        if (Math.abs(delta) < 1) return;
        for (let i = fromIndex + 1; i < state.layout.length; i++) {
            state.layout[i].top += delta;
        }
    }

    function totalContentHeight() {
        if (!state.layout.length) return 0;
        const last = state.layout[state.layout.length - 1];
        return last.top + last.height;
    }

    function findBlockIndexAtY(y) {
        const layout = state.layout;
        if (!layout.length) return 0;
        if (y <= layout[0].top) return 0;
        const last = layout.length - 1;
        if (y >= layout[last].top) return last;
        let lo = 0;
        let hi = last;
        while (lo < hi - 1) {
            const mid = (lo + hi) >> 1;
            if (layout[mid].top <= y) lo = mid;
            else hi = mid;
        }
        return lo;
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

    function visibleWindowIndicesFromScroll() {
        if (!state.layout.length || !hooks.getScrollTop) {
            return { startIndex: 0, endIndex: Math.max(0, state.layout.length - 1) };
        }
        const scrollEl = hooks.getScrollElement?.();
        const viewport = scrollEl?.clientHeight || 800;
        const scrollTop = hooks.getScrollTop();
        const lh = lineHeightPx();
        const startY = Math.max(0, scrollTop - cfg.buffer * lh);
        const endY = scrollTop + viewport + cfg.buffer * lh;
        return {
            startIndex: Math.max(0, findBlockIndexAtY(startY) - cfg.buffer),
            endIndex: Math.min(state.layout.length - 1, findBlockIndexAtY(endY) + cfg.buffer),
        };
    }

    function visibleWindowIndicesFromSource() {
        const win = hooks.getSourceLineWindow?.();
        if (!win || !state.layout.length) {
            return visibleWindowIndicesFromScroll();
        }
        const lineBuf = cfg.sourceLineBuffer ?? cfg.buffer;
        const blockBuf = Math.max(1, Math.ceil(cfg.buffer / 2));
        const startLine = Math.max(0, (win.startLine ?? 0) - lineBuf);
        const endLine = (win.endLine ?? win.startLine ?? 0) + lineBuf;
        return {
            startIndex: Math.max(0, findBlockIndexForSourceLine(startLine) - blockBuf),
            endIndex: Math.min(
                state.layout.length - 1,
                findBlockIndexForSourceLine(endLine) + blockBuf
            ),
        };
    }

    function visibleWindowIndices() {
        if (hooks.preferSourceLineWindow && hooks.getSourceLineWindow) {
            return visibleWindowIndicesFromSource();
        }
        return visibleWindowIndicesFromScroll();
    }

    function updateSpacers(startIndex, endIndex) {
        if (!state.topSpacer || !state.bottomSpacer) return;
        const layout = state.layout;
        const topPx = startIndex > 0 ? layout[startIndex].top : 0;
        const endEntry = layout[endIndex];
        const bottomStart = endEntry ? endEntry.top + endEntry.height : totalContentHeight();
        const bottomPx = Math.max(0, totalContentHeight() - bottomStart);
        state.topSpacer.style.height = `${topPx}px`;
        state.bottomSpacer.style.height = `${bottomPx}px`;
    }

    function unmountBlock(index) {
        const el = state.mounted.get(index);
        if (!el) return;
        el.remove();
        state.mounted.delete(index);
    }

    function applyMeasureBlock(index, el) {
        const entry = state.layout[index];
        if (!entry || !el) return;
        const next = Math.max(1, el.offsetHeight);
        if (Math.abs(next - entry.height) < 2) {
            entry.measured = true;
            return;
        }
        const delta = next - entry.height;
        entry.height = next;
        entry.measured = true;
        applyHeightDelta(index, delta);
    }

    function measureBlock(index, el) {
        if (state.isScrolling && !cfg.measureWhileScrolling) {
            state.pendingMeasure.add(index);
            return;
        }
        applyMeasureBlock(index, el);
    }

    function flushPendingMeasures() {
        if (!state.pendingMeasure.size) return;
        const indices = [...state.pendingMeasure].sort((a, b) => a - b);
        state.pendingMeasure.clear();
        for (const index of indices) {
            const el = state.mounted.get(index);
            if (el) applyMeasureBlock(index, el);
        }
        const { startIndex, endIndex } = visibleWindowIndices();
        updateSpacers(startIndex, endIndex);
    }

    function decorateBlockEl(index, el) {
        const block = state.blocks[index];
        if (!block) return;
        if (block.type === 'code-fence' && hooks.highlightCodeBlocks) {
            hooks.highlightCodeBlocks(el);
        }
        if (block.type === 'mermaid' && hooks.scheduleMermaid) {
            hooks.scheduleMermaid([el]);
        }
    }

    function mountBlock(index) {
        if (state.mounted.has(index)) return;
        const block = state.blocks[index];
        if (!block || !state.windowEl || !hooks.createBlockEl) return;
        const el = hooks.createBlockEl(block, index, { readOnly: state.readOnly });
        state.windowEl.appendChild(el);
        state.mounted.set(index, el);
        decorateBlockEl(index, el);
        if (cfg.measureWhileScrolling) {
            applyMeasureBlock(index, el);
        } else {
            requestAnimationFrame(() => measureBlock(index, el));
        }
    }

    function replaceBlockEl(index) {
        const block = state.blocks[index];
        if (!block || !hooks.createBlockEl) return;
        const newEl = hooks.createBlockEl(block, index, { readOnly: state.readOnly });
        const entry = state.layout[index];
        if (entry) {
            entry.height = estimateBlockHeight(block, lineHeightPx());
            entry.measured = false;
            entry.line = Number.isFinite(block.sourceLine) ? block.sourceLine : 0;
        }
        if (state.mounted.has(index)) {
            const oldEl = state.mounted.get(index);
            oldEl.replaceWith(newEl);
            state.mounted.set(index, newEl);
            decorateBlockEl(index, newEl);
            requestAnimationFrame(() => measureBlock(index, newEl));
        }
    }

    function syncWindow() {
        if (!state.active || !state.layout.length) return;
        if (!hooks.getSourceLineWindow && !hooks.getScrollTop) return;
        const { startIndex, endIndex } = visibleWindowIndices();

        for (const index of [...state.mounted.keys()]) {
            if (index < startIndex || index > endIndex) unmountBlock(index);
        }
        for (let i = startIndex; i <= endIndex; i++) mountBlock(i);
        updateSpacers(startIndex, endIndex);
    }

    function syncWindowFromSourceLines(startLine, endLine) {
        if (!state.active || !state.layout.length) return;
        const lineBuf = cfg.sourceLineBuffer ?? cfg.buffer;
        const blockBuf = Math.max(1, Math.ceil(cfg.buffer / 2));
        const startIndex = Math.max(
            0,
            findBlockIndexForSourceLine(Math.max(0, startLine - lineBuf)) - blockBuf
        );
        const endIndex = Math.min(
            state.layout.length - 1,
            findBlockIndexForSourceLine(endLine + lineBuf) + blockBuf
        );
        for (const index of [...state.mounted.keys()]) {
            if (index < startIndex || index > endIndex) unmountBlock(index);
        }
        for (let i = startIndex; i <= endIndex; i++) mountBlock(i);
        updateSpacers(startIndex, endIndex);
    }

    function scheduleSyncWindow() {
        if (state.scrollRaf) return;
        state.scrollRaf = requestAnimationFrame(() => {
            state.scrollRaf = 0;
            syncWindow();
        });
    }

    function shouldUse(blockCount, charLen) {
        return blockCount >= cfg.blockThreshold || charLen >= cfg.charThreshold;
    }

    function isActive() {
        return state.active;
    }

    function getLayout() {
        return state.layout;
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
        const lh = lineHeightPx();
        const frac = Math.max(0, Math.min(1, (line - seg.line + (subLinePx || 0) / lh) / lineSpan));
        const segHeight = next
            ? Math.max(seg.height, next.top - seg.top)
            : seg.height;
        return seg.top + frac * segHeight;
    }

    function getSourceLineForPreviewY(y) {
        const layout = state.layout;
        if (!layout.length) return 0;
        const idx = findBlockIndexAtY(y);
        const seg = layout[idx];
        const next = layout[idx + 1];
        const segHeight = next ? Math.max(seg.height, next.top - seg.top) : seg.height;
        const offset = Math.max(0, y - seg.top);
        const frac = segHeight > 0 ? Math.min(1, offset / segHeight) : 0;
        const lineSpan = next && next.line > seg.line ? next.line - seg.line : 8;
        return Math.max(0, seg.line + frac * lineSpan);
    }

    function mount(options) {
        teardown();
        hooks = options.hooks || {};
        cfg = { ...DEFAULTS, ...(options.config || {}) };
        state.blocks = options.blocks || [];
        state.footnotes = options.footnotes || null;
        state.readOnly = options.readOnly !== false;
        state.container = options.container;
        if (!state.container || !state.blocks.length) return false;

        buildLayout(state.blocks);
        state.container.innerHTML = '';
        state.topSpacer = document.createElement('div');
        state.topSpacer.className = 'preview-vspacer';
        state.windowEl = document.createElement('div');
        state.windowEl.className = 'preview-vwindow';
        state.bottomSpacer = document.createElement('div');
        state.bottomSpacer.className = 'preview-vspacer';
        state.container.appendChild(state.topSpacer);
        state.container.appendChild(state.windowEl);
        state.container.appendChild(state.bottomSpacer);

        if (hooks.appendFootnotes) {
            hooks.appendFootnotes(state.container, state.footnotes);
        }
        if (hooks.rewriteImages) {
            hooks.rewriteImages(state.container);
        }

        state.active = true;
        syncWindow();
        hooks.onReady?.(state.layout);
        return true;
    }

    function update(options) {
        if (!state.active || !state.container) {
            return mount(options);
        }
        if (options.container && options.container !== state.container) {
            return mount(options);
        }
        if (options.hooks) {
            hooks = { ...hooks, ...options.hooks };
        }

        const newBlocks = options.blocks || [];
        if (!newBlocks.length) {
            teardown();
            return false;
        }

        const oldBlocks = state.blocks;
        state.blocks = newBlocks;
        state.footnotes = options.footnotes ?? state.footnotes;
        state.readOnly = options.readOnly !== false;

        const sameStructure = oldBlocks.length === newBlocks.length
            && oldBlocks.every((block, index) => block.type === newBlocks[index].type);

        if (!sameStructure) {
            buildLayout(state.blocks);
            for (const index of [...state.mounted.keys()]) {
                unmountBlock(index);
            }
            syncWindow();
            hooks.onReady?.(state.layout);
            return true;
        }

        let firstChange = -1;
        for (let i = 0; i < newBlocks.length; i++) {
            if ((oldBlocks[i].source || '') !== (newBlocks[i].source || '')) {
                firstChange = i;
                break;
            }
        }

        if (firstChange < 0) {
            hooks.onReady?.(state.layout);
            return true;
        }

        for (let i = firstChange; i < newBlocks.length; i++) {
            if ((oldBlocks[i].source || '') === (newBlocks[i].source || '')) continue;
            replaceBlockEl(i);
        }
        rebuildLayoutFrom(firstChange);

        const { startIndex, endIndex } = visibleWindowIndices();
        updateSpacers(startIndex, endIndex);
        hooks.onReady?.(state.layout);
        return true;
    }

    function teardown() {
        state.active = false;
        state.blocks = [];
        state.layout = [];
        state.mounted.clear();
        state.pendingMeasure.clear();
        state.isScrolling = false;
        if (state.scrollIdleTimer) {
            clearTimeout(state.scrollIdleTimer);
            state.scrollIdleTimer = 0;
        }
        if (state.container) state.container.innerHTML = '';
        state.container = null;
        state.topSpacer = null;
        state.windowEl = null;
        state.bottomSpacer = null;
        hooks = {};
    }

    function onScroll() {
        state.isScrolling = true;
        if (state.scrollIdleTimer) clearTimeout(state.scrollIdleTimer);
        state.scrollIdleTimer = setTimeout(() => {
            state.scrollIdleTimer = 0;
            state.isScrolling = false;
            flushPendingMeasures();
            hooks.onLayoutSettled?.();
        }, 140);
        scheduleSyncWindow();
    }

    function flushLayoutMeasures() {
        if (state.scrollIdleTimer) {
            clearTimeout(state.scrollIdleTimer);
            state.scrollIdleTimer = 0;
        }
        state.isScrolling = false;
        flushPendingMeasures();
        hooks.onLayoutSettled?.();
    }

    function syncWindowNow() {
        syncWindow();
    }

    function configure(next) {
        cfg = { ...cfg, ...(next || {}) };
    }

    global.virtualPreview = {
        configure,
        shouldUse,
        isActive,
        mount,
        update,
        teardown,
        onScroll,
        scheduleSyncWindow,
        syncWindowNow,
        syncWindowFromSourceLines,
        flushLayoutMeasures,
        getLayout,
        getPreviewYForSourceLine,
        getSourceLineForPreviewY,
        totalContentHeight,
    };
})(window);
