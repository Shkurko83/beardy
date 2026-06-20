/**
 * X-Split: CM6 + virtual preview + line-anchored scroll sync (isolated module).
 * Source drives preview window; line positions scale between layout space and DOM scroll.
 */
(function experimentalEditorModule(global) {
    'use strict';

    const DEBOUNCE_MS = 600;
    const LEADER_HOLD_MS = 280;

    let hooks = {};
    let active = false;
    let updateTimer = 0;
    let preserveScrollOnMount = false;

    let scrollLeader = null;
    let leaderUntil = 0;
    let suppressEcho = null;

    let syncRaf = 0;
    let pendingSyncFrom = null;

    let sourceScrollHandler = null;
    let previewScrollHandler = null;
    const interactionCleanups = [];

    function now() {
        return performance.now();
    }

    function markLeader(who) {
        scrollLeader = who;
        leaderUntil = now() + LEADER_HOLD_MS;
    }

    function armEchoSuppress(pane) {
        suppressEcho = pane;
        requestAnimationFrame(() => {
            requestAnimationFrame(() => {
                if (suppressEcho === pane) suppressEcho = null;
            });
        });
    }

    function isOtherLeaderBlocking(myPane) {
        const other = myPane === 'source' ? 'preview' : 'source';
        return scrollLeader === other && now() < leaderUntil;
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
        if (from === 'source') syncFromSource();
        else syncFromPreview();
    }

    function scheduleScrollSync(from) {
        pendingSyncFrom = from;
        if (syncRaf) return;
        syncRaf = requestAnimationFrame(flushScrollSync);
    }

    function onSourceScroll() {
        if (!active || suppressEcho === 'source') return;
        if (isOtherLeaderBlocking('source')) return;
        markLeader('source');
        if (hooks.isVirtualPreviewActive?.()) {
            syncFromSource();
            return;
        }
        scheduleScrollSync('source');
    }

    function onPreviewScroll() {
        if (!active) return;
        if (suppressEcho === 'preview') return;
        if (isOtherLeaderBlocking('preview')) return;
        markLeader('preview');
        if (hooks.isVirtualPreviewActive?.()) {
            syncFromPreview();
            hooks.onPreviewViewportScroll?.();
            return;
        }
        hooks.onPreviewViewportScroll?.();
        scheduleScrollSync('preview');
    }

    function bindScrollInteraction() {
        const sourceEl = hooks.getSourceScrollEl?.();
        const previewEl = hooks.getPreviewScrollEl?.();

        const markSource = () => markLeader('source');
        const markPreview = () => markLeader('preview');

        sourceScrollHandler = onSourceScroll;
        previewScrollHandler = onPreviewScroll;
        sourceEl?.addEventListener('scroll', sourceScrollHandler, { passive: true });
        previewEl?.addEventListener('scroll', previewScrollHandler, { passive: true });

        for (const [el, mark] of [[sourceEl, markSource], [previewEl, markPreview]]) {
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
        markLeader('source');
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
        markLeader('source');
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
                if (saved) {
                    restoreSourceAnchor(saved);
                } else if (mountOpts.anchor) {
                    restoreScroll(mountOpts.anchor);
                } else {
                    markLeader('source');
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
        scrollLeader = null;
        leaderUntil = 0;
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

        mountPreview(options.text ?? hooks.getText?.() ?? '', {
            anchor: options.anchor,
            onComplete: options.onReady,
        });
        bindScrollInteraction();
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
        if (scrollLeader === 'preview') syncFromPreview();
        else syncFromSource();
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
