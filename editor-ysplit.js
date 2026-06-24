/**
 * Y-Split: MacDown-style split — instant CM6 editing, debounced preview render.
 * Smooth per-line scroll sync (primary); MacDown header anchors as fallback.
 */
(function ySplitEditorModule(global) {
    'use strict';

    const PREVIEW_DEBOUNCE_MS = 1200;
    const NATIVE_SYNC_DEBOUNCE_MS = 350;

    let hooks = {};
    let active = false;
    let previewTimer = 0;
    let nativeSyncTimer = 0;
    let preserveScrollOnMount = false;
    let pendingPreviewText = null;

    let editorAnchorYs = [];
    let previewAnchorYs = [];
    let anchorsReady = false;

    let syncRaf = 0;
    let syncingPreview = false;
    let previewUserNudge = false;
    let previewRefreshing = false;

    let sourceScrollHandler = null;
    let previewScrollHandler = null;
    const interactionCleanups = [];

    function updateHeaderLocations() {
        if (!global.ySplitSync) return;
        const paired = global.ySplitSync.buildPairedAnchors(hooks);
        editorAnchorYs = paired.editorAnchorYs;
        previewAnchorYs = paired.previewAnchorYs;
        anchorsReady = true;
    }

    function syncScrollers() {
        const sourceEl = hooks.getSourceScrollEl?.();
        const previewEl = hooks.getPreviewScrollEl?.();
        if (!active || !sourceEl || !previewEl || syncingPreview || previewUserNudge || previewRefreshing) return;

        let previewY;

        if (hooks.getPreviewYForSourceLine) {
            if (hooks.isVirtualPreviewActive?.()) {
                hooks.ensurePreviewForSourceViewport?.();
            }
            const line = hooks.getTopSourceLine?.() ?? 0;
            const sub = hooks.getSubLinePx?.() ?? 0;
            const layoutY = hooks.getPreviewYForSourceLine(line, sub) ?? 0;
            previewY = hooks.mapLayoutYToPreviewScroll?.(layoutY) ?? layoutY;
        } else if (global.ySplitSync) {
            if (!anchorsReady) updateHeaderLocations();
            previewY = global.ySplitSync.syncPreviewScrollFromEditor({
                editorScrollY: sourceEl.scrollTop,
                editorContentHeight: sourceEl.scrollHeight,
                editorVisibleHeight: sourceEl.clientHeight,
                previewContentHeight: previewEl.scrollHeight,
                previewVisibleHeight: previewEl.clientHeight,
                editorAnchorYs,
                previewAnchorYs,
            });
        } else {
            return;
        }

        const max = Math.max(0, previewEl.scrollHeight - previewEl.clientHeight);
        const next = Math.max(0, Math.min(previewY, max));
        if (Math.abs(previewEl.scrollTop - next) < 0.5) return;

        syncingPreview = true;
        if (hooks.setPreviewScrollTop) {
            hooks.setPreviewScrollTop(next);
        } else {
            previewEl.scrollTop = next;
        }
        requestAnimationFrame(() => {
            syncingPreview = false;
        });
    }

    function scheduleSyncScrollers() {
        if (syncRaf) return;
        syncRaf = requestAnimationFrame(() => {
            syncRaf = 0;
            syncScrollers();
        });
    }

    function onSourceScroll() {
        if (!active || syncingPreview || previewRefreshing) return;
        previewUserNudge = false;
        scheduleSyncScrollers();
    }

    function beginPreviewRefresh() {
        previewRefreshing = true;
    }

    function endPreviewRefresh(done) {
        requestAnimationFrame(() => {
            requestAnimationFrame(() => {
                previewRefreshing = false;
                done?.();
            });
        });
    }

    function onPreviewUserScroll() {
        if (!active || syncingPreview) return;
        if (hooks.isPreviewScrollSuppressed?.()) return;
        previewUserNudge = true;
    }

    function bindScrollInteraction() {
        unbindScrollInteraction();

        const sourceEl = hooks.getSourceScrollEl?.();
        const previewEl = hooks.getPreviewScrollEl?.();
        sourceScrollHandler = onSourceScroll;
        sourceEl?.addEventListener('scroll', sourceScrollHandler, { passive: true });

        previewScrollHandler = onPreviewUserScroll;
        previewEl?.addEventListener('scroll', previewScrollHandler, { passive: true });

        if (previewEl) {
            const markPreviewNudge = () => {
                if (!hooks.isPreviewScrollSuppressed?.()) previewUserNudge = true;
            };
            previewEl.addEventListener('wheel', markPreviewNudge, { passive: true, capture: true });
            previewEl.addEventListener('pointerdown', markPreviewNudge, { passive: true, capture: true });
            interactionCleanups.push(() => {
                previewEl.removeEventListener('wheel', markPreviewNudge, true);
                previewEl.removeEventListener('pointerdown', markPreviewNudge, true);
            });
        }
    }

    function unbindScrollInteraction() {
        const sourceEl = hooks.getSourceScrollEl?.();
        const previewEl = hooks.getPreviewScrollEl?.();
        sourceEl?.removeEventListener('scroll', sourceScrollHandler);
        previewEl?.removeEventListener('scroll', previewScrollHandler);
        sourceScrollHandler = null;
        previewScrollHandler = null;
        while (interactionCleanups.length) interactionCleanups.pop()();
        if (syncRaf) {
            cancelAnimationFrame(syncRaf);
            syncRaf = 0;
        }
    }

    function scheduleNativeSync(text) {
        clearTimeout(nativeSyncTimer);
        nativeSyncTimer = setTimeout(() => {
            nativeSyncTimer = 0;
            hooks.commitToNative?.(text ?? hooks.getEditorText?.() ?? '');
        }, NATIVE_SYNC_DEBOUNCE_MS);
    }

    function onEditorChange(value) {
        if (!active) return;
        pendingPreviewText = value;
        hooks.setEditorText?.(value);
        scheduleNativeSync(value);
        schedulePreviewRefresh();
    }

    function schedulePreviewRefresh() {
        clearTimeout(previewTimer);
        previewTimer = setTimeout(() => {
            previewTimer = 0;
            if (!active) return;
            const value = pendingPreviewText ?? hooks.getEditorText?.() ?? '';
            pendingPreviewText = null;
            const scrollAnchor = captureSourceAnchor();
            const previewEl = hooks.getPreviewScrollEl?.();
            if (previewEl) scrollAnchor.previewScrollTop = previewEl.scrollTop;
            beginPreviewRefresh();
            hooks.refreshPreview?.(value, {
                scrollAnchor,
                onComplete: () => {
                    endPreviewRefresh(() => {
                        if (!active) return;
                        anchorsReady = false;
                        updateHeaderLocations();
                    });
                },
            });
        }, PREVIEW_DEBOUNCE_MS);
    }

    function captureSourceAnchor() {
        return {
            line: hooks.getTopSourceLine?.() ?? 0,
            sub: hooks.getSubLinePx?.() ?? 0,
            percent: (() => {
                const sourceEl = hooks.getSourceScrollEl?.();
                if (!sourceEl) return 0;
                const max = Math.max(0, sourceEl.scrollHeight - sourceEl.clientHeight);
                return max > 0 ? sourceEl.scrollTop / max : 0;
            })(),
        };
    }

    function restoreSourceAnchor(anchor) {
        if (!anchor) return;
        const keepPreview = Number.isFinite(anchor.previewScrollTop);
        previewUserNudge = keepPreview;
        hooks.setSourceScrollForLine?.(anchor.line ?? 0, anchor.sub ?? 0);
        if (keepPreview) {
            hooks.setPreviewScrollTop?.(anchor.previewScrollTop);
            return;
        }
        requestAnimationFrame(() => {
            updateHeaderLocations();
            syncScrollers();
        });
    }

    function restoreScrollRatio(anchor) {
        const sourceEl = hooks.getSourceScrollEl?.();
        if (!sourceEl) return;
        previewUserNudge = false;
        const ratio = Math.max(0, Math.min(1, anchor?.percent ?? 0));
        const max = Math.max(0, sourceEl.scrollHeight - sourceEl.clientHeight);
        sourceEl.scrollTop = ratio * max;
        if (Number.isFinite(anchor?.previewScrollTop)) {
            previewUserNudge = true;
            hooks.setPreviewScrollTop?.(anchor.previewScrollTop);
            return;
        }
        requestAnimationFrame(() => {
            updateHeaderLocations();
            syncScrollers();
        });
    }

    function restoreAppearanceScroll(anchor) {
        if (!active || !anchor) return;
        if (Number.isFinite(anchor.line)) {
            restoreSourceAnchor(anchor);
            return;
        }
        restoreScrollRatio(anchor);
    }

    function finishPreviewMount(mountOpts, saved) {
        bindScrollInteraction();
        requestAnimationFrame(() => {
            updateHeaderLocations();
            if (saved) {
                restoreSourceAnchor(saved);
            } else if (mountOpts.anchor) {
                restoreScroll(mountOpts.anchor);
            } else {
                syncScrollers();
            }
            mountOpts.onComplete?.();
        });
    }

    function mountPreview(text, mountOpts = {}) {
        const saved = preserveScrollOnMount ? captureSourceAnchor() : null;
        anchorsReady = false;
        preserveScrollOnMount = false;
        hooks.mountPreview?.(text || hooks.getEditorText?.() || '', {
            onComplete: () => {
                if (!active) return;
                finishPreviewMount(mountOpts, saved);
            },
        });
    }

    function enter(options = {}) {
        leave();
        hooks = options.hooks || {};
        active = true;
        preserveScrollOnMount = false;
        previewUserNudge = false;
        pendingPreviewText = null;
        editorAnchorYs = [];
        previewAnchorYs = [];
        anchorsReady = false;

        document.body.classList.add('ysplit-active');

        const text = options.text ?? hooks.getEditorText?.() ?? '';
        const anchor = options.anchor;

        hooks.prepareSource?.({
            text,
            anchor,
            onChange: onEditorChange,
            onScroll: onSourceScroll,
        });

        if (anchor && Number.isFinite(anchor.line)) {
            hooks.setSourceScrollForLine?.(anchor.line, anchor.sub ?? 0);
        } else if (anchor && Number.isFinite(anchor.percent)) {
            const sourceEl = hooks.getSourceScrollEl?.();
            if (sourceEl) {
                const max = Math.max(0, sourceEl.scrollHeight - sourceEl.clientHeight);
                sourceEl.scrollTop = anchor.percent * max;
            }
        }

        hooks.deferPreviewMount?.(() => {
            if (!active) return;
            mountPreview(text, {
                anchor,
                onComplete: options.onReady,
            });
        });

        return true;
    }

    function leave() {
        if (!active) return null;
        const anchor = captureScrollAnchor();
        active = false;
        clearTimeout(previewTimer);
        clearTimeout(nativeSyncTimer);
        previewTimer = 0;
        nativeSyncTimer = 0;
        unbindScrollInteraction();
        hooks.teardownSource?.();
        hooks.teardownPreview?.();
        hooks.clearScrollMaps?.();
        document.body.classList.remove('ysplit-active');
        hooks = {};
        editorAnchorYs = [];
        previewAnchorYs = [];
        anchorsReady = false;
        previewUserNudge = false;
        return anchor;
    }

    function scheduleUpdate(text) {
        if (!active) return;
        onEditorChange(text);
    }

    function flushUpdate(text) {
        if (!active) return;
        clearTimeout(previewTimer);
        previewTimer = 0;
        const value = text ?? hooks.getEditorText?.() ?? '';
        pendingPreviewText = null;
        hooks.setEditorText?.(value);
        hooks.commitToNative?.(value);
        const scrollAnchor = captureSourceAnchor();
        const previewEl = hooks.getPreviewScrollEl?.();
        if (previewEl) scrollAnchor.previewScrollTop = previewEl.scrollTop;
        beginPreviewRefresh();
        hooks.refreshPreview?.(value, {
            scrollAnchor,
            onComplete: () => {
                endPreviewRefresh(() => {
                    if (!active) return;
                    anchorsReady = false;
                    updateHeaderLocations();
                });
            },
        });
    }

    function restoreScroll(anchor) {
        if (!active || !anchor) return;
        restoreAppearanceScroll(anchor);
    }

    function restoreAppearanceScrollPersistent(anchor) {
        if (!active || !anchor) return;
        restoreAppearanceScroll(anchor);
        requestAnimationFrame(() => {
            restoreAppearanceScroll(anchor);
            requestAnimationFrame(() => restoreAppearanceScroll(anchor));
        });
        [50, 120, 250, 400].forEach((delay) => {
            setTimeout(() => restoreAppearanceScroll(anchor), delay);
        });
    }

    function captureScrollAnchor() {
        return captureSourceAnchor();
    }

    function resyncAfterLayout() {
        if (!active || previewUserNudge || previewRefreshing) return;
        syncScrollers();
    }

    global.ySplitEditor = {
        enter,
        leave,
        scheduleUpdate,
        flushUpdate,
        restoreScroll,
        restoreAppearanceScrollPersistent,
        resyncAfterLayout,
        captureScrollAnchor,
        isActive: () => active,
        isSyncingPreview: () => syncingPreview,
        isPreviewUserNudge: () => previewUserNudge,
        isPreviewRefreshing: () => previewRefreshing,
    };
})(window);
