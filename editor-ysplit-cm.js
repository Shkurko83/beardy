/**
 * CodeMirror 6 source pane for Y-Split only (plain text, no syntax highlight).
 * Isolated from edit/split/X-Split source editors.
 */
(function ySplitCodeMirrorModule(global) {
    'use strict';

    let view = null;
    let updating = false;
    let hooks = {};
    let findRanges = [];
    let findCurrentIndex = -1;
    let findDirty = false;

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
        const mark = Decoration.mark({ class: 'cm-find-hit' });
        const markCurrent = Decoration.mark({ class: 'cm-find-hit-current' });
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

    function scrollToRange(start, end) {
        if (!view) return false;
        const doc = view.state.doc;
        const safeStart = Math.max(0, Math.min(start, doc.length));
        const safeEnd = Math.max(safeStart, Math.min(end, doc.length));
        const line = doc.lineAt(safeStart);
        const block = view.lineBlockAt(line.from);
        const viewport = view.scrollDOM.clientHeight || 0;
        view.scrollDOM.scrollTop = Math.max(0, block.top - Math.max(0, viewport * 0.25));
        // Keep find decoration colors visible — don't paint a selection over the hit.
        view.focus();
        return true;
    }

    function cmAvailable() {
        return !!(global.CM && global.CM.EditorView && global.CM.EditorState);
    }

    function isActive() {
        return !!view;
    }

    function getHost() {
        return document.getElementById('ysplit-cm-root');
    }

    function applyDomState(active) {
        const ta = document.getElementById('markdown-textarea');
        const host = getHost();
        document.body.classList.toggle('ysplit-cm-active', !!active);
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

    function mount(options = {}) {
        if (!cmAvailable()) {
            applyDomState(false);
            return null;
        }

        hooks = {
            onChange: options.onChange ?? hooks.onChange,
            onScroll: options.onScroll ?? hooks.onScroll,
        };

        const host = getHost();
        if (!host) return null;

        applyDomState(true);

        const text = options.initialText ?? '';

        if (view) {
            syncText(text);
            if (Number.isFinite(options.initialLine)) {
                setScrollTop(scrollForLine(options.initialLine, options.initialSub ?? 0));
            } else if (Number.isFinite(options.scrollTop)) {
                view.scrollDOM.scrollTop = options.scrollTop;
            }
            return view;
        }

        const { EditorView } = global.CM;
        let state;
        try {
            state = createEditorState(text, true);
        } catch (error) {
            console.warn('ySplitCodeMirror: find highlights disabled after mount error', error);
            state = createEditorState(text, false);
        }
        try {
            view = new EditorView({
                state,
                parent: host,
            });
        } catch (error) {
            console.error('ySplitCodeMirror mount failed:', error);
            applyDomState(false);
            return null;
        }

        view.scrollDOM.addEventListener('scroll', () => hooks.onScroll?.(), { passive: true });

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
        if (!view) {
            applyDomState(false);
            return null;
        }

        const text = view.state.doc.toString();
        view.destroy();
        view = null;
        hooks = {};
        applyDomState(false);
        return text;
    }

    function syncText(text) {
        if (!view) return;
        const incoming = String(text ?? '');
        if (view.state.doc.toString() === incoming) return;
        updating = true;
        view.dispatch({
            changes: { from: 0, to: view.state.doc.length, insert: incoming },
        });
        updating = false;
    }

    function getScrollElement() {
        return view?.scrollDOM ?? null;
    }

    function getTopSourceLine() {
        if (!view) return 0;
        const block = view.lineBlockAtHeight(view.scrollDOM.scrollTop);
        const line = view.state.doc.lineAt(block.from);
        return Math.max(0, line.number - 1);
    }

    function getSubLinePx() {
        if (!view) return 0;
        const scrollTop = view.scrollDOM.scrollTop;
        const block = view.lineBlockAtHeight(scrollTop);
        return Math.max(0, scrollTop - block.top);
    }

    /** MacDown anchor scan — approximate Y, called only for headings. */
    function getLineBlockY(lineIndex) {
        if (!view || lineIndex < 0) return 0;
        const lineN = Math.min(Math.max(1, lineIndex + 1), view.state.doc.lines);
        try {
            const lineObj = view.state.doc.line(lineN);
            const block = view.lineBlockAt(lineObj.from);
            return block.top;
        } catch {
            const lh = view.defaultLineHeight || 22.4;
            return 40 + lineIndex * lh;
        }
    }

    function scrollForLine(line, subLinePx) {
        if (!view) return 0;
        const lineN = Math.min(Math.max(1, line + 1), view.state.doc.lines);
        const lineObj = view.state.doc.line(lineN);
        const block = view.lineBlockAt(lineObj.from);
        return Math.max(0, block.top + (subLinePx || 0));
    }

    function setScrollTop(value) {
        if (!view) return;
        view.scrollDOM.scrollTop = value;
    }

    function getLineHeight() {
        if (!view) return 22.4;
        return view.defaultLineHeight || 22.4;
    }

    function getLineCount() {
        if (!view) return 1;
        return Math.max(1, view.state.doc.lines);
    }

    function refreshTheme() {
        // Y-Split CM theme is driven by body.dark + CSS; no remount (avoids scroll flicker).
    }

    function getContent() {
        return view ? view.state.doc.toString() : '';
    }

    function getVisibleSourceLineRange() {
        if (!view) return { startLine: 0, endLine: 0 };
        const scrollTop = view.scrollDOM.scrollTop;
        const viewport = view.scrollDOM.clientHeight;
        const topBlock = view.lineBlockAtHeight(scrollTop);
        const bottomBlock = view.lineBlockAtHeight(scrollTop + Math.max(viewport, 1));
        const startLine = Math.max(0, view.state.doc.lineAt(topBlock.from).number - 1);
        const endLine = Math.max(
            startLine,
            view.state.doc.lineAt(bottomBlock.from).number - 1
        );
        return { startLine, endLine };
    }

    function getLineBlockHeight(lineIndex) {
        if (!view) return getLineHeight();
        const lineN = Math.min(Math.max(1, lineIndex + 1), view.state.doc.lines);
        try {
            const lineObj = view.state.doc.line(lineN);
            const block = view.lineBlockAt(lineObj.from);
            return block.height || getLineHeight();
        } catch {
            return getLineHeight();
        }
    }

    function focusLineAt(lineNumber) {
        if (!view || lineNumber < 0) return false;
        const lineN = Math.min(lineNumber + 1, view.state.doc.lines);
        const lineObj = view.state.doc.line(lineN);
        view.dispatch({
            selection: { anchor: lineObj.from, head: lineObj.from },
        });
        view.focus();
        return true;
    }

    global.ySplitCodeMirror = {
        isActive,
        mount,
        unmount,
        syncText,
        getScrollElement,
        getTopSourceLine,
        getSubLinePx,
        getLineBlockY,
        scrollForLine,
        setScrollTop,
        getLineHeight,
        getLineCount,
        getContent,
        getVisibleSourceLineRange,
        getLineBlockHeight,
        focusLineAt,
        refreshTheme,
        setFindHighlights,
        clearFindHighlights,
        scrollToRange,
    };
})(window);
