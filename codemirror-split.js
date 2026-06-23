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

    function cmAvailable() {
        return !!(global.CM && global.CM.EditorView && global.CM.EditorState);
    }

    function isLargeDoc() {
        const ta = document.getElementById('markdown-textarea');
        const len = (ta?.value ?? global.currentContent ?? '').length;
        return len >= (global.LARGE_DOC_CHAR_THRESHOLD || 100000);
    }

    function shouldUseCm6() {
        if (!cmAvailable() || !isLargeDoc()) return false;
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

    function buildExtensions() {
        const { EditorView } = global.CM;
        return [
            EditorView.lineWrapping,
            buildTheme(),
            EditorView.updateListener.of((update) => {
                if (update.docChanged && !updating) {
                    hooks.onChange?.(update.state.doc.toString());
                }
            }),
        ];
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

        applyCm6DomState(true);

        if (view) {
            syncFromTextarea(options.initialText);
            if (Number.isFinite(options.initialLine)) {
                setScrollTop(scrollForLine(options.initialLine, options.initialSub ?? 0));
            } else if (Number.isFinite(options.scrollTop)) {
                setScrollTop(options.scrollTop);
            }
            return view;
        }

        const { EditorView, EditorState } = global.CM;
        const text = options.initialText ?? '';

        view = new EditorView({
            state: EditorState.create({
                doc: text,
                extensions: buildExtensions(),
            }),
            parent: host,
        });

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
        const safeEnd = Math.max(safeStart, Math.min(end, doc.length));
        const line = doc.lineAt(safeStart);
        const block = view.lineBlockAt(line.from);
        const viewport = view.scrollDOM.clientHeight || 0;
        view.scrollDOM.scrollTop = Math.max(0, block.top - Math.max(0, viewport * 0.25));
        view.dispatch({
            selection: { anchor: safeStart, head: safeEnd },
            scrollIntoView: true,
        });
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
    };

    global.sourceCodeMirror = api;
    global.splitCodeMirror = api;
})(window);
