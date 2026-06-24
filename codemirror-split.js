/**
 * CodeMirror 6 source pane for large documents (Edit + Split).
 * Plain text only — no markdown syntax highlighting (matches X-Split).
 * Requires editor.bundle.js (window.CM) loaded first. Offline.
 */
(function sourceCodeMirrorModule(global) {
    'use strict';

    let view = null;
    let updating = false;
    let hooks = {};
    let scrollHandler = null;
    let findRanges = [];
    let findCurrentIndex = -1;
    let findDirty = false;
    let cmMountDisabled = false;

    function normalizeFindRanges(ranges) {
        return (ranges || []).map((range) => {
            const start = Number(range.start ?? range.location ?? range.from ?? 0);
            const end = Number(range.end ?? (start + (range.length ?? 0)));
            if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return null;
            return { start, end };
        }).filter(Boolean);
    }

    function buildFindHighlightExtension() {
        const { ViewPlugin, Decoration } = global.CM;
        if (!ViewPlugin || !Decoration) return [];
        const mark = Decoration.mark({
            class: 'cm-find-hit',
            attributes: { style: 'background-color: rgba(255, 214, 10, 0.45); border-radius: 2px; color: inherit;' },
        });
        const markCurrent = Decoration.mark({
            class: 'cm-find-hit-current',
            attributes: { style: 'background-color: rgba(255, 149, 0, 0.72); border-radius: 2px; box-shadow: 0 0 0 1px rgba(255, 149, 0, 0.9); color: inherit;' },
        });
        return ViewPlugin.fromClass(class {
            constructor(view) { this.decorations = this.buildDeco(view); }
            update(update) {
                if (findRanges.length || findDirty || update.docChanged) {
                    findDirty = false;
                    this.decorations = findRanges.length
                        ? this.buildDeco(update.view)
                        : Decoration.none;
                }
            }
            buildDeco(view) {
                if (!findRanges.length) return Decoration.none;
                const items = findRanges.map((range, index) => {
                    const from = Math.max(0, Math.min(range.start, view.state.doc.length));
                    const to = Math.max(from, Math.min(range.end, view.state.doc.length));
                    if (to <= from) return null;
                    return (index === findCurrentIndex ? markCurrent : mark).range(from, to);
                }).filter(Boolean);
                return Decoration.set(items, true);
            }
        }, { decorations: (plugin) => plugin.decorations });
    }

    function setFindHighlights(ranges, currentIndex) {
        findRanges = normalizeFindRanges(ranges);
        findCurrentIndex = Number.isFinite(currentIndex) ? currentIndex : -1;
        findDirty = true;
        if (view) view.dispatch({});
    }

    function clearFindHighlights() {
        findRanges = [];
        findCurrentIndex = -1;
        findDirty = true;
        if (view) view.dispatch({});
    }

    function cmAvailable() {
        return !!(global.CM && global.CM.EditorView && global.CM.EditorState);
    }

    function isLargeDoc() {
        const ta = document.getElementById('markdown-textarea');
        const len = (ta?.value ?? global.currentContent ?? '').length;
        return len >= (global.LARGE_DOC_CHAR_THRESHOLD || 100000);
    }

    function shouldUseCm6() {
        if (cmMountDisabled || !cmAvailable() || !isLargeDoc()) return false;
        const body = document.body;
        return body.classList.contains('mode-split') || body.classList.contains('mode-edit');
    }

    function isActive() {
        return !!view && shouldUseCm6();
    }

    function getView() {
        return view;
    }

    function applyCm6DomState(active) {
        document.body.classList.toggle('cm6-source-active', !!active);
        const ta = document.getElementById('markdown-textarea');
        const host = document.getElementById('codemirror-split-root');
        if (ta) ta.style.display = active ? 'none' : '';
        if (host) host.style.display = active ? 'block' : 'none';
    }

    function buildTheme() {
        const { EditorView } = global.CM;
        const isDark = document.body.classList.contains('dark');
        return EditorView.theme({
            '&': {
                height: '100%',
                backgroundColor: 'transparent',
                color: 'inherit',
            },
            '.cm-scroller': {
                overflow: 'auto',
                fontFamily: 'var(--editor-font-family)',
                fontSize: 'var(--editor-font-size)',
                lineHeight: 'var(--editor-line-height)',
                tabSize: 'var(--editor-tab-size)',
                padding: '40px 60px',
            },
            '.cm-content': {
                fontFamily: 'inherit',
                fontSize: 'inherit',
                lineHeight: 'inherit',
                caretColor: isDark ? '#58a6ff' : '#0969da',
                color: 'inherit',
            },
            '.cm-line': { color: 'inherit' },
            '.cm-gutters': { display: 'none !important' },
            '.cm-activeLine': { backgroundColor: 'transparent' },
            '.cm-activeLineGutter': { backgroundColor: 'transparent' },
            '.cm-lineNumbers': { display: 'none !important' },
            '&.cm-focused': { outline: 'none' },
            '.cm-selectionBackground': {
                backgroundColor: isDark ? 'rgba(56, 139, 253, 0.28)' : 'rgba(9, 105, 218, 0.22)',
            },
        }, { dark: isDark });
    }

    function buildExtensions(includeFindHighlights = true) {
        const { EditorView } = global.CM;
        return [
            EditorView.lineWrapping,
            buildTheme(),
            ...(includeFindHighlights ? buildFindHighlightExtension() : []),
            EditorView.updateListener.of((update) => {
                if (update.docChanged && !updating) {
                    hooks.onChange?.(update.state.doc.toString());
                }
            }),
        ];
    }

    function createEditorState(text, includeFindHighlights = true) {
        const { EditorState } = global.CM;
        return EditorState.create({
            doc: text,
            extensions: buildExtensions(includeFindHighlights),
        });
    }

    function resolveInitialText(options = {}) {
        if (options.initialText != null) return String(options.initialText);
        const ta = document.getElementById('markdown-textarea');
        return ta?.value ?? global.currentContent ?? '';
    }

    function mount(options = {}) {
        if (!shouldUseCm6()) {
            applyCm6DomState(false);
            return null;
        }

        hooks = {
            onChange: options.onChange,
            onScroll: options.onScroll,
        };

        const host = document.getElementById('codemirror-split-root');
        if (!host) return null;

        const text = resolveInitialText(options);

        if (view) {
            applyCm6DomState(true);
            syncFromTextarea(text);
            if (Number.isFinite(options.initialLine)) {
                setScrollTop(scrollForLine(options.initialLine, options.initialSub ?? 0));
            } else if (Number.isFinite(options.scrollTop)) {
                setScrollTop(options.scrollTop);
            }
            return view;
        }

        const { EditorView } = global.CM;
        let state;
        try {
            state = createEditorState(text, true);
        } catch (error) {
            console.warn('sourceCodeMirror: find highlights disabled after mount error', error);
            try {
                state = createEditorState(text, false);
            } catch (retryError) {
                console.error('sourceCodeMirror: EditorState.create failed', retryError);
                cmMountDisabled = true;
                applyCm6DomState(false);
                return null;
            }
        }

        try {
            view = new EditorView({
                state,
                parent: host,
            });
        } catch (error) {
            console.error('sourceCodeMirror mount failed:', error);
            cmMountDisabled = true;
            applyCm6DomState(false);
            return null;
        }

        applyCm6DomState(true);

        scrollHandler = () => hooks.onScroll?.();
        view.scrollDOM.addEventListener('scroll', scrollHandler, { passive: true });

        if (Number.isFinite(options.initialLine)) {
            view.scrollDOM.scrollTop = scrollForLine(options.initialLine, options.initialSub ?? 0);
        } else if (Number.isFinite(options.scrollTop)) {
            view.scrollDOM.scrollTop = options.scrollTop;
        }
        if (options.focus) {
            view.focus();
        }

        return view;
    }

    function unmount() {
        cmMountDisabled = false;
        if (!view) {
            applyCm6DomState(false);
            return null;
        }

        const text = view.state.doc.toString();
        if (scrollHandler) {
            view.scrollDOM.removeEventListener('scroll', scrollHandler);
            scrollHandler = null;
        }
        view.destroy();
        view = null;
        hooks = {};
        applyCm6DomState(false);
        return text;
    }

    function ensure(options = {}) {
        if (!shouldUseCm6()) {
            if (view) unmount();
            return null;
        }
        return mount(options);
    }

    function syncFromTextarea(text) {
        if (!view) return;
        const incoming = String(text ?? '');
        const current = view.state.doc.toString();
        if (current === incoming) return;

        updating = true;
        view.dispatch({
            changes: { from: 0, to: view.state.doc.length, insert: incoming },
        });
        updating = false;
    }

    function getContent() {
        return view ? view.state.doc.toString() : '';
    }

    function refreshTheme() {
        if (!view) return;
        const line = getTopSourceLine();
        const sub = getSubLinePx();
        const sel = view.state.selection.main;
        const text = view.state.doc.toString();
        const savedOnChange = hooks.onChange;
        const savedOnScroll = hooks.onScroll;
        unmount();
        mount({
            initialText: text,
            onChange: savedOnChange,
            onScroll: savedOnScroll,
        });
        const restore = () => {
            setScrollTop(scrollForLine(line, sub));
            if (view) {
                view.dispatch({ selection: { anchor: sel.anchor, head: sel.head } });
            }
        };
        requestAnimationFrame(() => {
            requestAnimationFrame(restore);
        });
    }

    function getScrollElement() {
        return view?.scrollDOM ?? null;
    }

    function getTopSourceLine() {
        if (!view) return 0;
        const scrollTop = view.scrollDOM.scrollTop;
        const block = view.lineBlockAtHeight(scrollTop);
        const line = view.state.doc.lineAt(block.from);
        return Math.max(0, line.number - 1);
    }

    function getSubLinePx() {
        if (!view) return 0;
        const scrollTop = view.scrollDOM.scrollTop;
        const block = view.lineBlockAtHeight(scrollTop);
        return Math.max(0, scrollTop - block.top);
    }

    function scrollForLine(line, subLinePx) {
        if (!view) return 0;
        const lineN = Math.min(Math.max(1, line + 1), view.state.doc.lines);
        const lineObj = view.state.doc.line(lineN);
        const block = view.lineBlockAt(lineObj.from);
        return Math.max(0, block.top + (subLinePx || 0));
    }

    function scrollToLine(lineNumber) {
        if (!view || lineNumber < 0) return false;
        const lineN = Math.min(lineNumber + 1, view.state.doc.lines);
        const lineObj = view.state.doc.line(lineN);
        const block = view.lineBlockAt(lineObj.from);
        view.scrollDOM.scrollTop = Math.max(0, block.top);
        view.dispatch({
            selection: { anchor: lineObj.from, head: lineObj.from },
            scrollIntoView: true,
        });
        view.focus();
        return true;
    }

    function scrollToRange(start, end) {
        if (!view) return false;
        const doc = view.state.doc;
        const safeStart = Math.max(0, Math.min(start, doc.length));
        const line = doc.lineAt(safeStart);
        const block = view.lineBlockAt(line.from);
        const viewport = view.scrollDOM.clientHeight || 0;
        view.scrollDOM.scrollTop = Math.max(0, block.top - Math.max(0, viewport * 0.25));
        view.dispatch({ selection: { anchor: safeStart, head: safeStart } });
        view.focus();
        return true;
    }

    function setScrollTop(value) {
        if (!view) return;
        view.scrollDOM.scrollTop = value;
    }

    const api = {
        shouldUseCm6,
        isActive,
        getView,
        mount,
        unmount,
        ensure,
        syncFromTextarea,
        getContent,
        refreshTheme,
        getScrollElement,
        getTopSourceLine,
        getSubLinePx,
        scrollForLine,
        scrollToLine,
        scrollToRange,
        setScrollTop,
        setFindHighlights,
        clearFindHighlights,
    };

    global.sourceCodeMirror = api;
    global.splitCodeMirror = api;
})(window);
