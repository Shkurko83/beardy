/**
 * MacDown-style header/image anchor scroll sync (MPDocument.m PR #933).
 * Paired source↔preview anchors by source line (our renderer uses .live-block, not h1 tags).
 * Falls back to linear ratio when too few paired anchors (MacDown pre-933 behaviour).
 * https://github.com/MacDownApp/macdown
 */
(function ySplitSyncModule(global) {
    'use strict';

    const ATX_HEADER = /^(#+)\s/;
    const SETEXT_DASH = /^([-]+)$/;
    const STANDALONE_IMG = /^!\[[^\]]*\]\([^)]*\)$/;

    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function scanStandaloneImageLineIndices(text) {
        const lines = String(text ?? '').split('\n');
        const indices = [];
        for (let i = 0; i < lines.length; i++) {
            if (STANDALONE_IMG.test(lines[i])) {
                indices.push(i);
            }
        }
        return indices;
    }

    /**
     * Build parallel editor/preview anchor arrays (same length, same structural element).
     * @param {object} hooks
     * @returns {{ editorAnchorYs: number[], previewAnchorYs: number[] }}
     */
    function buildPairedAnchors(hooks) {
        const sourceEl = hooks.getSourceScrollEl?.();
        if (!sourceEl) {
            return { editorAnchorYs: [], previewAnchorYs: [] };
        }

        const lh = hooks.getSourceLineHeight?.() ?? 22.4;
        const contentH = sourceEl.scrollHeight;
        const visibleH = sourceEl.clientHeight;
        const cutoff = Math.max(0, contentH - visibleH);
        const seenLines = new Set();

        const editorAnchorYs = [];
        const previewAnchorYs = [];

        function tryAdd(lineIndex) {
            if (seenLines.has(lineIndex)) return;
            const sourceTop = hooks.getSourceLineY?.(lineIndex) ?? 0;
            const sourceY = sourceTop + lh * 0.5;
            if (sourceY > cutoff) return;
            const previewY = hooks.getPreviewTopForSourceLine?.(lineIndex);
            if (!Number.isFinite(previewY)) return;
            seenLines.add(lineIndex);
            editorAnchorYs.push(sourceY);
            previewAnchorYs.push(previewY);
        }

        const headings = hooks.getDocumentHeadings?.() ?? [];
        for (const heading of headings) {
            if (Number.isFinite(heading?.lineNumber)) {
                tryAdd(heading.lineNumber);
            }
        }

        const text = hooks.getText?.() ?? '';
        for (const lineIndex of scanStandaloneImageLineIndices(text)) {
            tryAdd(lineIndex);
        }

        return { editorAnchorYs, previewAnchorYs };
    }

    /** Center-of-viewport taper from MacDown syncScrollers. */
    function computeCenterAdjustment(currY, contentHeight, visibleHeight) {
        if (visibleHeight <= 0) return 0;
        const topTaper = clamp(currY / visibleHeight, 0, 1);
        const bottomTaper = 1 - clamp(
            (currY - contentHeight + 2 * visibleHeight) / visibleHeight,
            0,
            1
        );
        return topTaper * bottomTaper * visibleHeight / 2;
    }

    /** MacDown pre-933 linear scroll ratio. */
    function linearRatioPreviewScroll(params) {
        const {
            editorScrollY,
            editorContentHeight,
            editorVisibleHeight,
            previewContentHeight,
            previewVisibleHeight,
        } = params;
        const editorMax = Math.max(0, editorContentHeight - editorVisibleHeight);
        const previewMax = Math.max(0, previewContentHeight - previewVisibleHeight);
        if (editorMax <= 0) return 0;
        const ratio = clamp(editorScrollY / editorMax, 0, 1);
        return ratio * previewMax;
    }

    /**
     * MacDown syncScrollers — requires paired anchors of equal length (>= 2).
     */
    function macDownPreviewScroll(params) {
        const {
            editorScrollY,
            editorContentHeight,
            editorVisibleHeight,
            previewContentHeight,
            previewVisibleHeight,
            editorAnchorYs,
            previewAnchorYs,
        } = params;

        let relativeHeaderIndex = -1;
        let currY = editorScrollY;
        let minY = 0;
        let maxY = null;

        const adjustment = computeCenterAdjustment(
            currY,
            editorContentHeight,
            editorVisibleHeight
        );

        for (const headerY of editorAnchorYs) {
            const adjusted = headerY - adjustment;
            if (adjusted < currY) {
                relativeHeaderIndex += 1;
                minY = adjusted;
            } else if (maxY == null && adjusted < editorContentHeight - editorVisibleHeight) {
                maxY = adjusted;
            }
        }

        let interpolateToEnd = false;
        if (maxY == null) {
            maxY = editorContentHeight - editorVisibleHeight + adjustment;
            interpolateToEnd = true;
        }

        currY = Math.max(0, currY - minY);
        maxY -= minY;
        const span = maxY > 0 ? maxY : 1;
        const percent = clamp(currY / span, 0, 1);

        let topHeaderY = 0;
        let bottomHeaderY = previewContentHeight - previewVisibleHeight;

        if (previewAnchorYs.length > relativeHeaderIndex) {
            topHeaderY = Math.floor(previewAnchorYs[relativeHeaderIndex]) - adjustment;
        }
        if (!interpolateToEnd && previewAnchorYs.length > relativeHeaderIndex + 1) {
            bottomHeaderY = Math.ceil(previewAnchorYs[relativeHeaderIndex + 1]) - adjustment;
        }

        return topHeaderY + (bottomHeaderY - topHeaderY) * percent;
    }

    /**
     * Map editor scrollTop → preview scrollTop (one-way, MacDown style).
     */
    function syncPreviewScrollFromEditor(params) {
        const editorAnchors = params.editorAnchorYs ?? [];
        const previewAnchors = params.previewAnchorYs ?? [];
        const paired = editorAnchors.length >= 2
            && previewAnchors.length >= 2
            && editorAnchors.length === previewAnchors.length;

        if (!paired) {
            return linearRatioPreviewScroll(params);
        }
        return macDownPreviewScroll(params);
    }

    function mapDocYAcrossLineTops(sourceTops, targetTops, docY) {
        const n = sourceTops?.length ?? 0;
        if (!n || !targetTops?.length) return docY;
        if (docY <= sourceTops[0]) return targetTops[0];
        if (docY >= sourceTops[n - 1]) return targetTops[n - 1];
        let lo = 0;
        let hi = n - 1;
        while (lo < hi - 1) {
            const mid = (lo + hi) >> 1;
            if (sourceTops[mid] <= docY) lo = mid;
            else hi = mid;
        }
        const span = sourceTops[hi] - sourceTops[lo];
        const t = span > 0 ? (docY - sourceTops[lo]) / span : 0;
        return targetTops[lo] + t * (targetTops[hi] - targetTops[lo]);
    }

    global.ySplitSync = {
        buildPairedAnchors,
        computeCenterAdjustment,
        linearRatioPreviewScroll,
        macDownPreviewScroll,
        syncPreviewScrollFromEditor,
        mapDocYAcrossLineTops,
    };
})(window);
