//
//  codemirror-script.js
//  Beardy2
//
//  Created by Butt Simpson on 07.01.2026.
//

let leftView, rightView;
let isSyncing = false;
let currentContent = '';
let isInitialized = false;
alert('JavaScript загружен!');
console.log('🎉 СКРИПТ ЗАГРУЖЕН!');

function initializeEditor(initialText = '', isDark = false) {
    console.log('🚀 Инициализация редактора...');
    
    const { EditorView, EditorState, basicSetup, markdown } = window.CM;
    
    if (isDark) {
        document.body.classList.add('dark');
    }

    currentContent = initialText;

    // Левый редактор (обычный Markdown)
    leftView = new EditorView({
        state: EditorState.create({
            doc: initialText,
            extensions: [
                basicSetup,
                markdown(),
                EditorView.lineWrapping,
                EditorView.updateListener.of(update => {
                    if (update.docChanged && !isSyncing && isInitialized) {
                        const newContent = update.state.doc.toString();
                        syncToRight(newContent);
                    }
                })
            ]
        }),
        parent: document.getElementById('left-editor')
    });

    // Правый редактор (Live Preview)
    rightView = new EditorView({
        state: EditorState.create({
            doc: initialText,
            extensions: [
                basicSetup,
                markdown(),
                EditorView.lineWrapping,
                EditorView.theme({
                    ".cm-lineNumbers": { display: "none" },
                    ".cm-gutters": { display: "none" }
                }),
                EditorView.updateListener.of(update => {
                    if (update.docChanged && !isSyncing && isInitialized) {
                        const newContent = update.state.doc.toString();
                        syncToLeft(newContent);
                    }
                    
                    // ВАЖНО: применяем стили после КАЖДОГО изменения
                    if (update.docChanged || update.viewportChanged) {
                        setTimeout(() => {
                            applyMarkdownStyles();
                        }, 0);
                    }
                })
            ]
        }),
        parent: document.getElementById('right-editor')
    });

    // Применяем стили сразу после инициализации
    setTimeout(() => {
        applyMarkdownStyles();
        isInitialized = true;
        console.log('✅ Редакторы инициализированы');
        
        // Проверяем что стили применились
        setTimeout(() => {
            const codeBlocks = document.querySelectorAll('#right-editor .cm-line[data-code-block]');
            const tables = document.querySelectorAll('#right-editor .cm-line[data-table-row]');
            console.log('📊 Найдено блоков кода:', codeBlocks.length);
            console.log('📊 Найдено строк таблиц:', tables.length);
        }, 500);
    }, 200);
}

function syncToRight(text) {
    if (!rightView || isSyncing) return;
    
    isSyncing = true;
    currentContent = text;
    
    rightView.dispatch({
        changes: { from: 0, to: rightView.state.doc.length, insert: text }
    });
    
    if (window.webkit?.messageHandlers?.contentChanged) {
        window.webkit.messageHandlers.contentChanged.postMessage(text);
    }
    
    setTimeout(() => {
        applyMarkdownStyles();
        isSyncing = false;
    }, 50);
}

function syncToLeft(text) {
    if (!leftView || isSyncing) return;
    
    isSyncing = true;
    currentContent = text;
    
    leftView.dispatch({
        changes: { from: 0, to: leftView.state.doc.length, insert: text }
    });
    
    if (window.webkit?.messageHandlers?.contentChanged) {
        window.webkit.messageHandlers.contentChanged.postMessage(text);
    }
    
    isSyncing = false;
}

function applyMarkdownStyles() {
    const rightEditor = document.getElementById('right-editor');
    if (!rightEditor) {
        console.warn('⚠️ right-editor не найден');
        return;
    }

    const lines = rightEditor.querySelectorAll('.cm-line');
    console.log('🔍 Обрабатываем строк:', lines.length);
    
    let inCodeBlock = false;
    let codeBlockLines = [];
    let codeLanguage = '';
    let inTable = false;
    let tableLines = [];
    let processedCode = 0;
    let processedTable = 0;
    
    lines.forEach((line, index) => {
        const text = line.textContent;
        
        // Сброс всех атрибутов
        line.removeAttribute('data-level');
        line.removeAttribute('data-code-fence');
        line.removeAttribute('data-code-block');
        line.removeAttribute('data-code-lang');
        line.removeAttribute('data-table-row');
        line.removeAttribute('data-table-separator');
        line.removeAttribute('data-quote');
        line.removeAttribute('data-hr');
        
        // === ЗАГОЛОВКИ ===
        const headerMatch = text.match(/^(#{1,6})\s/);
        if (headerMatch && !inCodeBlock) {
            line.setAttribute('data-level', headerMatch[1].length);
        }
        
        // === БЛОКИ КОДА ===
        if (text.trim().startsWith('```')) {
            if (!inCodeBlock) {
                // Открывающий fence
                inCodeBlock = true;
                line.setAttribute('data-code-fence', 'open');
                
                // Извлекаем язык
                const langMatch = text.match(/```(\w+)/);
                codeLanguage = langMatch ? langMatch[1] : 'code';
                console.log('📝 Начало блока кода, язык:', codeLanguage);
                
                codeBlockLines = [];
            } else {
                // Закрывающий fence
                inCodeBlock = false;
                line.setAttribute('data-code-fence', 'close');
                
                console.log('📝 Конец блока кода, строк:', codeBlockLines.length);
                
                // Помечаем строки блока кода
                if (codeBlockLines.length === 1) {
                    codeBlockLines[0].setAttribute('data-code-block', 'single');
                    codeBlockLines[0].setAttribute('data-code-lang', codeLanguage);
                    processedCode++;
                } else if (codeBlockLines.length > 1) {
                    codeBlockLines[0].setAttribute('data-code-block', 'first');
                    codeBlockLines[0].setAttribute('data-code-lang', codeLanguage);
                    
                    for (let i = 1; i < codeBlockLines.length - 1; i++) {
                        codeBlockLines[i].setAttribute('data-code-block', 'middle');
                    }
                    
                    codeBlockLines[codeBlockLines.length - 1].setAttribute('data-code-block', 'last');
                    processedCode += codeBlockLines.length;
                }
                
                codeBlockLines = [];
                codeLanguage = '';
            }
        } else if (inCodeBlock) {
            codeBlockLines.push(line);
            line.setAttribute('data-code-block', 'middle');
        }
        
        // === ТАБЛИЦЫ === (только если НЕ в блоке кода)
        if (!inCodeBlock) {
            if (text.trim().startsWith('|')) {
                if (!inTable) {
                    inTable = true;
                    tableLines = [];
                    console.log('📊 Начало таблицы');
                }
                
                // Проверяем разделитель |-----|
                if (/^\|[\s\-:|]+\|$/.test(text.trim())) {
                    line.setAttribute('data-table-separator', 'true');
                    console.log('  Разделитель таблицы');
                } else {
                    tableLines.push(line);
                    if (tableLines.length === 1) {
                        line.setAttribute('data-table-row', 'header');
                        console.log('  Заголовок таблицы');
                    } else {
                        line.setAttribute('data-table-row', 'body');
                        console.log('  Строка таблицы');
                    }
                    processedTable++;
                }
            } else if (inTable) {
                // Конец таблицы
                console.log('📊 Конец таблицы, строк:', tableLines.length);
                if (tableLines.length > 0) {
                    const firstRow = tableLines[0];
                    const currentAttr = firstRow.getAttribute('data-table-row');
                    firstRow.setAttribute('data-table-row', currentAttr + ' first');
                    
                    const lastRow = tableLines[tableLines.length - 1];
                    const lastAttr = lastRow.getAttribute('data-table-row');
                    lastRow.setAttribute('data-table-row', lastAttr + ' last');
                }
                inTable = false;
                tableLines = [];
            }
            
            // === ЦИТАТЫ ===
            if (text.trim().startsWith('>')) {
                line.setAttribute('data-quote', 'true');
            }
            
            // === ГОРИЗОНТАЛЬНАЯ ЛИНИЯ ===
            if (/^(\*{3,}|-{3,}|_{3,})$/.test(text.trim())) {
                line.setAttribute('data-hr', 'true');
            }
        }
        
        // === INLINE ФОРМАТИРОВАНИЕ ===
        if (!inCodeBlock) {
            markInlineStyles(line);
        }
    });
    
    // Закрываем таблицу если она последняя
    if (inTable && tableLines.length > 0) {
        const firstRow = tableLines[0];
        const currentAttr = firstRow.getAttribute('data-table-row');
        firstRow.setAttribute('data-table-row', currentAttr + ' first');
        
        const lastRow = tableLines[tableLines.length - 1];
        const lastAttr = lastRow.getAttribute('data-table-row');
        lastRow.setAttribute('data-table-row', lastAttr + ' last');
    }
    
    console.log('✅ Обработано блоков кода:', processedCode, 'строк таблиц:', processedTable);
}

function markInlineStyles(line) {
    const spans = line.querySelectorAll('span');
    const lineText = line.textContent;
    
    spans.forEach((span, spanIndex) => {
        span.removeAttribute('data-strong');
        span.removeAttribute('data-em');
        span.removeAttribute('data-inline-code');
        
        const text = span.textContent;
        const allSpans = Array.from(spans);
        
        // === INLINE КОД `код` ===
        if (text !== '`' && lineText.includes('`')) {
            const beforeSpans = allSpans.slice(0, spanIndex);
            const afterSpans = allSpans.slice(spanIndex + 1);
            
            const backticksBefore = beforeSpans.filter(s => s.textContent === '`').length;
            const backticksAfter = afterSpans.filter(s => s.textContent === '`').length;
            
            // Если нечётное количество бэктиков до и есть бэктики после
            if (backticksBefore % 2 === 1 && backticksAfter > 0) {
                span.setAttribute('data-inline-code', 'true');
            }
        }
        
        // === ЖИРНЫЙ **текст** ===
        if (text !== '**' && text !== '__' && (lineText.includes('**') || lineText.includes('__'))) {
            const beforeSpans = allSpans.slice(0, spanIndex);
            const afterSpans = allSpans.slice(spanIndex + 1);
            
            const strongBefore = beforeSpans.filter(s => s.textContent === '**' || s.textContent === '__').length;
            const strongAfter = afterSpans.filter(s => s.textContent === '**' || s.textContent === '__').length;
            
            if (strongBefore % 2 === 1 && strongAfter > 0) {
                span.setAttribute('data-strong', 'true');
            }
        }
        
        // === КУРСИВ *текст* ===
        if (text !== '*' && text !== '_' && (lineText.includes('*') || lineText.includes('_'))) {
            // Только если это не часть ** (жирного)
            if (!span.hasAttribute('data-strong')) {
                const beforeSpans = allSpans.slice(0, spanIndex);
                const afterSpans = allSpans.slice(spanIndex + 1);
                
                const emBefore = beforeSpans.filter(s => (s.textContent === '*' || s.textContent === '_') && s.textContent.length === 1).length;
                const emAfter = afterSpans.filter(s => (s.textContent === '*' || s.textContent === '_') && s.textContent.length === 1).length;
                
                if (emBefore % 2 === 1 && emAfter > 0) {
                    span.setAttribute('data-em', 'true');
                }
            }
        }
    });
}

// API для Swift
window.cmEditor = {
    updateContent: (text) => {
        if (!leftView || !rightView) {
            console.warn('⚠️ Редакторы не готовы');
            return;
        }
        
        console.log('📥 Обновление из Swift');
        isSyncing = true;
        currentContent = text;
        
        leftView.dispatch({
            changes: { from: 0, to: leftView.state.doc.length, insert: text }
        });
        
        rightView.dispatch({
            changes: { from: 0, to: rightView.state.doc.length, insert: text }
        });
        
        setTimeout(() => {
            applyMarkdownStyles();
            isSyncing = false;
        }, 100);
    },
    
    setTheme: (isDark) => {
        console.log('🎨 Смена темы:', isDark);
        if (isDark) {
            document.body.classList.add('dark');
        } else {
            document.body.classList.remove('dark');
        }
    },
    
    setViewMode: (mode) => {
        console.log('🖥️ Смена режима:', mode);
        document.body.className = document.body.className.replace(/mode-\w+/g, '');
        document.body.classList.add(`mode-${mode}`);
        
        if (document.body.classList.contains('dark')) {
            document.body.classList.add('dark');
        }
    },
    
    getContent: () => currentContent
};

window.initializeEditor = initializeEditor;
console.log('✅ cmEditor API готов');
