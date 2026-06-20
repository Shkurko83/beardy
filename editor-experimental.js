/**
 * X-Split: CM6 + virtual preview + line-anchored scroll sync (isolated module).
 * Both panes stay aligned by source line; preview scrollTop maps 1:1 to layout Y.
 */
(function experimentalEditorModule(global) {
    'use strict';

    const DEBOUNCE_MS = 600;

    let hooks = {};
    let active = false;
    let updateTimer = 0;
    let preserveScrollOnMount = false;

    let suppressEcho = null;

    let syncRaf = 0;
    let pendingSyncFrom = null;

    let sourceScrollHandler = null;
    let previewScrollHandler = null;
    const interactionCleanups = [];

    function armEchoSuppress(pane) {
        suppressEcho = pane;
        requestAnimationFrame(() => {
            requestAnimationFrame(() => {
                requestAnimationFrame(() => {
                    if (suppressEcho === pane) suppressEcho = null;
                });
            });
        });
    }

    function syncFromSource() {
        if (hooks.isVirtualPreviewActive?.()) {
            hooks.ensurePreviewForSourceViewport?.();
            const line = hooks.getTopSourceLine?.() ?? 0;
            const sub = hooks.getSubLinePx?.() ?? 0;
            const layoutY = hooks.getPreviewYForSourceLine?.(line, sub) ?? 0;
            const scrollY = hooks.mapLayoutYToPreviewScroll?.(layoutY) ?? layoutY;
            armEchoSuppress('preview');
            hooks.setPreviewScrollTop?.(scrollY, { fromSource: true });
            return;
        }

        const line = hooks.getTopSourceLine?.() ?? 0;
        const sub = hooks.getSubLinePx?.() ?? 0;
        const previewY = hooks.mapSourceLineToPreviewY?.(line, sub) ?? 0;
        armEchoSuppress('preview');
        hooks.setPreviewScrollTop?.(previewY);
    }

    function syncFromPreview() {
        if (hooks.isVirtualPreviewActive?.()) {
            const scrollTop = hooks.getPreviewDocY?.() ?? 0;
            const layoutY = hooks.mapPreviewScrollToLayoutY?.(scrollTop) ?? scrollTop;
            const lineFrac = hooks.getSourceLineForLayoutY?.(layoutY) ?? 0;
            const maxLine = Math.max(0, (hooks.getSourceLineCount?.() ?? 1) - 1);
            const clamped = Math.min(Math.max(0, lineFrac), maxLine + 0.999);
            const line = Math.floor(clamped);
            const sub = (clamped - line) * (hooks.getSourceLineHeight?.() ?? 22.4);
            armEchoSuppress('source');
            hooks.setSourceScrollForLine?.(line, sub);
            hooks.ensurePreviewForSourceViewport?.();
            return;
        }

        const previewY = hooks.getPreviewDocY?.() ?? 0;
        const mapped = hooks.mapPreviewYToSourceLine?.(previewY);
        armEchoSuppress('source');
        hooks.setSourceScrollForLine?.(mapped?.line ?? 0, mapped?.sub ?? 0);
    }

    function flushScrollSync() {
        syncRaf = 0;
        const from = pendingSyncFrom;
        pendingSyncFrom = null;
        if (!active || !from) return;
        if (from === 'source') {
            syncFromSource();
            return;
        }
        syncFromPreview();
        hooks.onPreviewViewportScroll?.();
    }

    function scheduleScrollSync(from) {
        pendingSyncFrom = from;
        if (syncRaf) return;
        syncRaf = requestAnimationFrame(flushScrollSync);
    }

    function onSourceScroll() {
        if (!active || suppressEcho === 'source') return;
        scheduleScrollSync('source');
    }

    function onPreviewScroll() {
        if (!active || suppressEcho === 'preview') return;
        scheduleScrollSync('preview');
    }

    function bindScrollInteraction() {
        unbindScrollInteraction();

        const sourceEl = hooks.getSourceScrollEl?.();
        const previewEl = hooks.getPreviewScrollEl?.();

        sourceScrollHandler = onSourceScroll;
        previewScrollHandler = onPreviewScroll;
        sourceEl?.addEventListener('scroll', sourceScrollHandler, { passive: true });
        previewEl?.addEventListener('scroll', previewScrollHandler, { passive: true });

        for (const [el, mark] of [[sourceEl, () => {}], [previewEl, () => {}]]) {
            if (!el) continue;
            el.addEventListener('wheel', mark, { passive: true, capture: true });
            el.addEventListener('pointerdown', mark, { passive: true, capture: true });
            interactionCleanups.push(() => {
                el.removeEventListener('wheel', mark, true);
                el.removeEventListener('pointerdown', mark, true);
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
        pendingSyncFrom = null;
    }

    function captureSourceAnchor() {
        return {
            line: hooks.getTopSourceLine?.() ?? 0,
            sub: hooks.getSubLinePx?.() ?? 0,
        };
    }

    function restoreSourceAnchor(anchor) {
        if (!anchor) return;
        armEchoSuppress('source');
        hooks.setSourceScrollForLine?.(anchor.line ?? 0, anchor.sub ?? 0);
        armEchoSuppress('preview');
        syncFromSource();
    }

    function restoreScrollRatio(anchor) {
        const sourceEl = hooks.getSourceScrollEl?.();
        if (!sourceEl) return;
        const ratio = Math.max(0, Math.min(1, anchor?.percent ?? 0));
        const max = Math.max(0, sourceEl.scrollHeight - sourceEl.clientHeight);
        armEchoSuppress('source');
        sourceEl.scrollTop = ratio * max;
        armEchoSuppress('preview');
        syncFromSource();
    }

    function mountPreview(text, mountOpts = {}) {
        const saved = preserveScrollOnMount ? captureSourceAnchor() : null;
        hooks.mountPreview?.(text || hooks.getText?.() || '', {
            onComplete: () => {
                if (!active) return;
                bindScrollInteraction();
                if (saved) {
                    restoreSourceAnchor(saved);
                } else if (mountOpts.anchor) {
                    restoreScroll(mountOpts.anchor);
                } else {
                    syncFromSource();
                }
                mountOpts.onComplete?.();
            },
        });
    }

    function enter(options = {}) {
        leave();
        hooks = options.hooks || {};
        active = true;
        preserveScrollOnMount = false;
        suppressEcho = null;

        document.body.classList.add('experimental-active');
        hooks.prepareSource?.({
            text: options.text ?? hooks.getText?.() ?? '',
            onChange: (value) => {
                if (!active) return;
                hooks.syncTextareaValue?.(value);
                scheduleUpdate(value);
            },
            onScroll: onSourceScroll,
        });

        bindScrollInteraction();
        mountPreview(options.text ?? hooks.getText?.() ?? '', {
            anchor: options.anchor,
            onComplete: options.onReady,
        });
        return true;
    }

    function leave() {
        if (!active) return null;
        const anchor = captureScrollAnchor();
        active = false;
        clearTimeout(updateTimer);
        updateTimer = 0;
        unbindScrollInteraction();
        hooks.teardownSource?.();
        hooks.teardownPreview?.();
        document.body.classList.remove('experimental-active');
        hooks = {};
        return anchor;
    }

    function scheduleUpdate(text) {
        if (!active) return;
        preserveScrollOnMount = true;
        clearTimeout(updateTimer);
        updateTimer = setTimeout(() => {
            updateTimer = 0;
            const value = text ?? hooks.getText?.() ?? '';
            hooks.syncSourceText?.(value);
            mountPreview(value);
        }, DEBOUNCE_MS);
    }

    function flushUpdate(text) {
        if (!active) return;
        preserveScrollOnMount = true;
        clearTimeout(updateTimer);
        const value = text ?? hooks.getText?.() ?? '';
        hooks.syncSourceText?.(value);
        mountPreview(value);
    }

    function restoreScroll(anchor) {
        if (!active) return;
        if (Number.isFinite(anchor?.line)) {
            restoreSourceAnchor({ line: anchor.line, sub: anchor.sub ?? 0 });
            return;
        }
        restoreScrollRatio(anchor);
    }

    function captureScrollAnchor() {
        return {
            percent: (() => {
                const sourceEl = hooks.getSourceScrollEl?.();
                if (!sourceEl) return 0;
                const max = Math.max(0, sourceEl.scrollHeight - sourceEl.clientHeight);
                return max > 0 ? sourceEl.scrollTop / max : 0;
            })(),
            line: hooks.getTopSourceLine?.() ?? 0,
            sub: hooks.getSubLinePx?.() ?? 0,
        };
    }

    function resyncAfterLayout() {
        if (!active) return;
        scheduleScrollSync('source');
    }

    global.experimentalEditor = {
        enter,
        leave,
        scheduleUpdate,
        flushUpdate,
        restoreScroll,
        resyncAfterLayout,
        captureScrollAnchor,
        isActive: () => active,
    };
})(window);
