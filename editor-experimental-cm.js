/**
 * CodeMirror 6 source pane for X-Split only (plain text, no syntax highlight).
 * Isolated from edit/split sourceCodeMirror.
 */
(function experimentalCodeMirrorModule(global) {
    'use strict';

    let view = null;
    let updating = false;
    let hooks = {};

    function cmAvailable() {
        return !!(global.CM && global.CM.EditorView && global.CM.EditorState);
    }

    function isActive() {
        return !!view;
    }

    function getHost() {
        return document.getElementById('experimental-cm-root');
    }

    function applyDomState(active) {
        const ta = document.getElementById('markdown-textarea');
        const host = getHost();
        document.body.classList.toggle('experimental-cm-active', !!active);
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
        if (!cmAvailable()) {
            applyDomState(false);
            return null;
        }

        hooks = {
            onChange: options.onChange,
            onScroll: options.onScroll,
        };

        const host = getHost();
        if (!host) return null;

        applyDomState(true);

        const text = options.initialText ?? '';

        if (view) {
            syncText(text);
            if (Number.isFinite(options.scrollTop)) {
                view.scrollDOM.scrollTop = options.scrollTop;
            }
            return view;
        }

        const { EditorView, EditorState } = global.CM;
        view = new EditorView({
            state: EditorState.create({
                doc: text,
                extensions: buildExtensions(),
            }),
            parent: host,
        });

        view.scrollDOM.addEventListener('scroll', () => hooks.onScroll?.(), { passive: true });

        if (Number.isFinite(options.scrollTop)) {
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
        if (!view) return;
        const line = getTopSourceLine();
        const sub = getSubLinePx();
        const text = view.state.doc.toString();
        unmount();
        mount({ initialText: text });
        setScrollTop(scrollForLine(line, sub));
    }

    global.experimentalCodeMirror = {
        isActive,
        mount,
        unmount,
        syncText,
        getScrollElement,
        getTopSourceLine,
        getVisibleSourceLineRange,
        getSubLinePx,
        scrollForLine,
        setScrollTop,
        getLineHeight,
        getLineCount,
        refreshTheme,
    };
})(window);
