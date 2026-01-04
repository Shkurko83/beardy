import SwiftUI

struct EditorView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var themeService: ThemeService
    @State private var showOutline = false
    @State private var outlineWidth: CGFloat = 200
    @State private var showStatisticsPanel = false
    @State private var showFindPanel = false
    @Binding var scrollPosition: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                // Editor Toolbar
                EditorToolbar()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                
                HStack(spacing: 0) {
                    // Main Editor Area
                    ZStack {
                        switch documentManager.viewMode {
                        case .edit:
                            MarkdownEditorArea(scrollPosition: $scrollPosition)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .preview:
                            MarkdownPreviewArea(editorScrollPosition: $scrollPosition)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            
                        case .split:
                            HSplitView {
                                MarkdownEditorArea(scrollPosition: $scrollPosition)
                                    .frame(minWidth: 300)
                                
                                MarkdownPreviewArea(editorScrollPosition: $scrollPosition)
                                    .frame(minWidth: 300)
                            }
                        }
                    }
                    
                    // Outline Sidebar
                    if showOutline {
                        Divider()
                        
                        OutlineView()
                            .frame(width: outlineWidth)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: {
                    withAnimation {
                        showOutline.toggle()
                    }
                }) {
                    Image(systemName: "list.bullet.indent")
                }
                .help("Toggle Outline")
            }
        }
        .sheet(isPresented: $showStatisticsPanel) {
            if let doc = documentManager.currentDocument {
                FullStatisticsPanel(statistics: DocumentStatistics(from: doc.content))
            }
        }
        // ← Добавьте overlay для Find & Replace
        .overlay(alignment: .top) {
            if showFindPanel, let doc = documentManager.currentDocument {
                FindReplacePanel(
                    isPresented: $showFindPanel,
                    textContent: .constant(doc.content),
                    selectedRange: .constant(NSRange(location: 0, length: 0))
                )
                .padding(.top, 60)
            }
        }
    }
}

// MARK: - Markdown Editor Area
struct MarkdownEditorArea: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var themeService: ThemeService
    @State private var textContent: String = ""
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var fontSize: CGFloat = 16
    @State private var lineHeight: CGFloat = 1.6
    @State private var textViewReference: NSTextView?
    @FocusState private var isEditorFocused: Bool
    @State private var showFindPanel = false
    
    @AppStorage("previewSyncScroll") private var previewSyncScroll: Bool = true
    @Binding var scrollPosition: CGFloat
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Text Editor - БЕЗ внешнего ScrollView
            MarkdownTextEditor(
                text: $textContent,
                selectedRange: $selectedRange,
                scrollPosition: $scrollPosition,
                fontSize: fontSize,
                lineHeight: lineHeight,
                textViewReference: $textViewReference,
                focusMode: documentManager.focusMode,
                typewriterMode: documentManager.typewriterMode
            )
            .id(documentManager.currentDocument?.id)
            .focused($isEditorFocused)
        }
//        .background(themeService.currentTheme.colors.background)
        .onAppear {
            loadDocumentContent()
            isEditorFocused = true
        }
        .onChange(of: documentManager.currentDocument?.id) { _, _ in
            loadDocumentContent()
        }
        .onChange(of: textContent) { _, newValue in
            if documentManager.currentDocument?.content != newValue {
                documentManager.updateContent(newValue)
            }
        }
        .findReplacePanel(
            isPresented: $showFindPanel,
            textContent: $textContent,
            selectedRange: $selectedRange
        )
        .onReceive(NotificationCenter.default.publisher(for: .showFindPanel)) { _ in
            showFindPanel = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showReplacePanel)) { _ in
            showFindPanel = true
        }
    }
    
    private func loadDocumentContent() {
        if let doc = documentManager.currentDocument {
            textContent = doc.content
        } else {
            textContent = ""
        }
    }
}

// MARK: - Editor Toolbar
struct EditorToolbar: View {
    @EnvironmentObject var documentManager: DocumentManager
    
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 16) {
                // Text formatting
                ToolbarButton(icon: "bold", tooltip: "Bold (⌘B)") {
                    documentManager.toggleBold()
                }
                
                ToolbarButton(icon: "italic", tooltip: "Italic (⌘I)") {
                    documentManager.toggleItalic()
                }
                
                ToolbarButton(icon: "strikethrough", tooltip: "Strikethrough") {
                    documentManager.toggleStrikethrough()
                }
                
                Divider()
                    .frame(height: 20)
                
                // Headings
                Menu {
                    ForEach(1...6, id: \.self) { level in
                        Button("Heading \(level)") {
                            documentManager.insertHeading(level: level)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat.size")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(height: 24)
                
                Divider()
                    .frame(height: 20)
                
                // Lists
                ToolbarButton(icon: "list.bullet", tooltip: "Bullet List") {
                    documentManager.insertBulletList()
                }
                
                ToolbarButton(icon: "list.number", tooltip: "Numbered List") {
                    documentManager.insertNumberedList()
                }
                
                ToolbarButton(icon: "checklist", tooltip: "Task List") {
                    documentManager.insertTaskList()
                }
                
                Divider()
                    .frame(height: 20)
                
                // Insert elements
                ToolbarButton(icon: "link", tooltip: "Insert Link (⌘K)") {
                    documentManager.insertLink()
                }
                
                ToolbarButton(icon: "photo", tooltip: "Insert Image") {
                    documentManager.insertImage()
                }
                
                ToolbarButton(icon: "tablecells", tooltip: "Insert Table") {
                    documentManager.insertTable()
                }
                
                ToolbarButton(icon: "chevron.left.forwardslash.chevron.right", tooltip: "Code Block") {
                    documentManager.insertCodeBlock()
                }
                
                Divider()
                    .frame(height: 20)
                
                // Special
                ToolbarButton(icon: "quote.opening", tooltip: "Blockquote") {
                    documentManager.insertBlockquote()
                }
                
                ToolbarButton(icon: "minus.forwardslash.plus", tooltip: "Horizontal Rule") {
                    documentManager.insertHorizontalRule()
                }
                
                Spacer()
            }
            
            // Line/Word count
            if let doc = documentManager.currentDocument {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10))
                        Text("\(doc.lineCount) lines")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10))
                        Text("\(doc.wordCount) words")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "character")
                            .font(.system(size: 10))
                        Text("\(doc.characterCount) chars")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Toolbar Button
struct ToolbarButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 24, height: 24)
                .background(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Markdown Text Editor (NSViewRepresentable)
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var scrollPosition: CGFloat
    @EnvironmentObject var themeService: ThemeService
    
    let fontSize: CGFloat
    let lineHeight: CGFloat
    @Binding var textViewReference: NSTextView?
    let focusMode: Bool
    let typewriterMode: Bool
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        // Configure scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        // Configure text view
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        
        // Layout
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        // Configure appearance
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = NSColor(themeService.currentTheme.colors.text)
        textView.backgroundColor = NSColor(themeService.currentTheme.colors.background)
        textView.insertionPointColor = NSColor.controlAccentColor
        
        // Set text container properties
        if let textContainer = textView.textContainer {
            textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textContainer.widthTracksTextView = true
            textContainer.lineFragmentPadding = 0
        }
        
        // Устанавливаем отступы
        let horizontalPadding: CGFloat = focusMode ? 120 : 60
        let verticalPadding: CGFloat = 40
        textView.textContainerInset = NSSize(width: horizontalPadding, height: verticalPadding)
        
        // Configure paragraph style
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeight
        paragraphStyle.paragraphSpacing = 8
        textView.defaultParagraphStyle = paragraphStyle
        
        // Устанавливаем максимальную ширину для typewriter mode
        if typewriterMode, let textContainer = textView.textContainer {
            textContainer.containerSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)
            textContainer.widthTracksTextView = false
        }
        
        // Устанавливаем начальный текст
        textView.string = text
        context.coordinator.textView = textView
        // Сохраняем ссылку
        DispatchQueue.main.async {
            self.textViewReference = textView
        }
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        let theme = themeService.currentTheme
        let textColor = NSColor(theme.colors.text)
        let backgroundColor = NSColor(theme.colors.background)
        
        // Обновляем фон и текст
        if textView.backgroundColor != backgroundColor {
            textView.backgroundColor = backgroundColor
        }
        if textView.textColor != textColor {
            textView.textColor = textColor
        }
        
        // Цвет курсора (каретки)
        textView.insertionPointColor = .blue
        
        // Обновляем ссылку если изменилась
        if textViewReference !== textView {
            DispatchQueue.main.async {
                self.textViewReference = textView
            }
        }
        
        // Обновляем текст только если он действительно изменился
        if textView.string != text && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            textView.string = text
            context.coordinator.isUpdating = false
        }
        
        // Update font size if changed
        if let currentFont = textView.font, currentFont.pointSize != fontSize {
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        
        // Обновляем отступы при изменении режимов
        let horizontalPadding: CGFloat = focusMode ? 120 : 60
        let verticalPadding: CGFloat = 40
        let currentInset = textView.textContainerInset
        if currentInset.width != horizontalPadding || currentInset.height != verticalPadding {
            textView.textContainerInset = NSSize(width: horizontalPadding, height: verticalPadding)
        }
        
        // Обновляем ширину контейнера для typewriter mode
        if let textContainer = textView.textContainer {
            if typewriterMode {
                if textContainer.containerSize.width != 800 {
                    textContainer.containerSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)
                    textContainer.widthTracksTextView = false
                }
            } else {
                if !textContainer.widthTracksTextView {
                    textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
                    textContainer.widthTracksTextView = true
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        var textView: NSTextView?
        var isUpdating = false
        
        init(_ parent: MarkdownTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isUpdating else { return }
            
            isUpdating = true
            parent.text = textView.string
            parent.selectedRange = textView.selectedRange()
            isUpdating = false
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isUpdating else { return }
            let newRange = textView.selectedRange()
            if parent.selectedRange != newRange {
                DispatchQueue.main.async {
                    self.parent.selectedRange = newRange
                }
            }
        }
        
        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let scrollView = notification.object as? NSClipView else { return }
            let position = scrollView.bounds.origin.y
            DispatchQueue.main.async {
                self.parent.scrollPosition = position
            }
        }
    }
}

// MARK: - Markdown Preview Area
struct MarkdownPreviewArea: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var themeService: ThemeService
    @AppStorage("codeBlockTheme") private var codeBlockTheme: String = "github-dark"
    @AppStorage("showCodeLineNumbers") private var showCodeLineNumbers: Bool = false
    @AppStorage("previewSyncScroll") private var previewSyncScroll: Bool = true
    @Binding var editorScrollPosition: CGFloat
    
    var body: some View {
        Group {
            if let doc = documentManager.currentDocument {
                MarkdownRenderer(
                    markdown: doc.content,
                    textColor: themeService.currentTheme.colors.text.description,
                    isDark: themeService.currentTheme.id.contains("dark"),
                    codeTheme: codeBlockTheme,
                    showLineNumbers: showCodeLineNumbers,
                    scrollPosition: previewSyncScroll ? editorScrollPosition : 0
                )
            } else {
                Color.clear
            }
        }
        .background(themeService.currentTheme.colors.background)
    }
}

// MARK: - Outline View
struct OutlineView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var themeService: ThemeService
    @State private var headings: [HeadingItem] = []
    @State private var updateTask: Task<Void, Never>? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Outline")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    refreshOutline(immediately: true)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            // Headings list
            ScrollView {
                if headings.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        
                        Text("No headings")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(headings) { heading in
                            OutlineHeadingRow(heading: heading) {
                                documentManager.scrollToHeading(heading)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .background(themeService.currentTheme.colors.background)
        .foregroundStyle(themeService.currentTheme.colors.text)
        .onChange(of: documentManager.currentDocument?.content) { _, _ in
            refreshOutline(immediately: false)
        }
        .onAppear {
            refreshOutline(immediately: true)
        }
    }
    
    private func refreshOutline(immediately: some Any) {
        // Отменяем старую задачу, если начали печатать снова
        updateTask?.cancel()
        
        updateTask = Task {
            // Если не нажата кнопка "Обновить", ждем 300мс перед парсингом
            if !(immediately as? Bool ?? false) {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            
            if Task.isCancelled { return }
            
            if let content = documentManager.currentDocument?.content {
                let newHeadings = parseHeadings(from: content)
                
                await MainActor.run {
                    self.headings = newHeadings
                }
            }
        }
    }
    
    private func parseHeadings(from markdown: String) -> [HeadingItem] {
        var result: [HeadingItem] = []
        let lines = markdown.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Заголовок должен начинаться с # и иметь пробел после них
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" })
                let level = hashes.count
                
                // Проверяем, что уровень от 1 до 6 и после них идет пробел
                if level <= 6 {
                    let suffix = trimmed.dropFirst(level)
                    if suffix.hasPrefix(" ") || suffix.isEmpty {
                        let title = suffix.trimmingCharacters(in: .whitespaces)
                        if !title.isEmpty {
                            result.append(HeadingItem(level: level, title: title, lineNumber: index))
                        }
                    }
                }
            }
        }
        
        return result
    }
}

// MARK: - Outline Heading Row
struct OutlineHeadingRow: View {
    let heading: HeadingItem
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Indentation based on level
                Spacer()
                    .frame(width: CGFloat((heading.level - 1) * 12))
                
                // Level indicator
                Circle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 6, height: 6)
                
                // Title
                Text(heading.title)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Heading Item Model
struct HeadingItem: Identifiable {
    let id = UUID()
    let level: Int
    let title: String
    let lineNumber: Int
}
