import SwiftUI

struct EditorView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var themeService: ThemeService
    @AppStorage(AppConstants.Keys.outlinePanelWidth) private var outlinePanelWidth: Double = AppConstants.Defaults.outlineWidth
    @AppStorage(AppConstants.Keys.sidebarPanelWidth) private var sidebarPanelWidth: Double = AppConstants.Defaults.sidebarWidth
    @State private var showStatisticsPanel = false
    @Binding var scrollPosition: CGFloat
    let windowWidth: CGFloat
    let resolvedOutlineWidth: CGFloat
    @Binding var outlineWidthDuringDrag: CGFloat?
    let onOutlineDragEnded: (CGFloat) -> Void

    private var displayOutlineWidth: CGFloat {
        outlineWidthDuringDrag ?? resolvedOutlineWidth
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Group {
                    if documentManager.viewMode == .diff {
                        DiffEditorArea()
                    } else {
                        MarkdownEditorArea(scrollPosition: $scrollPosition)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                if documentManager.showOutline {
                    HStack(spacing: 0) {
                        PanelResizeHandle(
                            width: displayOutlineWidth,
                            windowWidth: windowWidth,
                            sidebarVisible: documentManager.showSidebar,
                            outlineVisible: documentManager.showOutline,
                            sidebarPreferred: CGFloat(sidebarPanelWidth),
                            outlinePreferred: outlineWidthDuringDrag ?? CGFloat(outlinePanelWidth),
                            edge: .trailingPanel,
                            onWidthChange: { outlineWidthDuringDrag = $0 },
                            onDragEnded: {
                                onOutlineDragEnded(outlineWidthDuringDrag ?? displayOutlineWidth)
                            }
                        )
                        .environmentObject(themeService)

                        OutlineView()
                            .frame(width: displayOutlineWidth)
                            .frame(maxHeight: .infinity)
                            .clipped()
                    }
                    .transition(PanelLayoutAnimation.trailingPanel)
                }
            }
            .animation(PanelLayoutAnimation.slide, value: documentManager.showOutline)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(nil, value: outlineWidthDuringDrag)
            .transaction { transaction in
                if outlineWidthDuringDrag != nil {
                    transaction.animation = nil
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .animation(nil, value: documentManager.viewMode)
        .animation(nil, value: themeService.appearanceToken)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: {
                    withAnimation(PanelLayoutAnimation.slide) {
                        documentManager.showOutline.toggle()
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
    }
}



// MARK: - Markdown Editor Area с CodeMirror
struct MarkdownEditorArea: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var themeService: ThemeService
    @StateObject private var mountState = TabWebViewMountState()
    @State private var textContent: String = ""
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @FocusState private var isEditorFocused: Bool
    @State private var suppressContentSync = false

    @AppStorage(AppConstants.Keys.previewSyncScroll) private var previewSyncScroll: Bool = true
    @Binding var scrollPosition: CGFloat

    var body: some View {
        Group {
            if let selectedID = documentManager.selectedTabID,
               let tab = documentManager.tabs.first(where: { $0.id == selectedID }) {
                CodeMirrorWebView(
                    tabID: selectedID,
                    isSelected: true,
                    text: activeTextBinding,
                    selectedRange: $selectedRange,
                    currentDocumentURL: tab.document.url,
                    isDark: themeService.isDarkMode,
                    viewMode: documentManager.viewMode,
                    editorTheme: themeService.currentTheme,
                    codeBlockTheme: themeService.currentCodeTheme,
                    appearanceToken: themeService.appearanceToken
                )
                .id(selectedID)
            }
        }
        .focused($isEditorFocused)
        .onAppear {
            documentManager.onPrepareTabMount = { id in
                mountState.markVisited(id, documentManager: documentManager)
            }
            if let id = documentManager.selectedTabID {
                syncActiveTabContent()
                mountState.markVisited(id, documentManager: documentManager)
            }
            isEditorFocused = true
            EditorAppearanceSync.pushToEditor()
            EditorSettingsSync.pushToEditor()
            TypingSettingsSync.pushToEditor()
        }
        .onChange(of: documentManager.selectedTabID) { _, newID in
            syncActiveTabContent()
            if let newID {
                mountState.markVisited(newID, documentManager: documentManager)
            }
            documentManager.refreshStatisticsForCurrentTab()
            EditorAppearanceSync.pushToEditor()
        }
        .onDisappear {
            documentManager.onPrepareTabMount = nil
        }
        .onChange(of: documentManager.tabs.map(\.id)) { _, ids in
            mountState.pruneClosedTabs(openTabIDs: Set(ids))
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorTabDidClose)) { notification in
            guard let tabID = notification.object as? UUID else { return }
            mountState.forget(tabID, documentManager: documentManager)
        }
        .onChange(of: textContent) { _, newValue in
            guard !suppressContentSync else { return }
            guard let tabID = documentManager.selectedTabID,
                  documentManager.isTabEditorReady(tabID) else { return }
            documentManager.updateContent(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorHistoryContentApplied)) { notification in
            guard let content = notification.object as? String,
                  let tabID = documentManager.selectedTabID else { return }
            suppressContentSync = true
            textContent = content
            suppressContentSync = false
            EditorWebViewPool.shared.pushContent(tabID: tabID, content: content)
        }
        .onChange(of: previewSyncScroll) { _, enabled in
            EditorExecJS.post("window.cmEditor?.setSyncScroll(\(enabled));", target: .activeTab)
        }
        .onChange(of: documentManager.focusMode) { _, _ in
            EditorAppearanceSync.pushFocusMode()
        }
        .onChange(of: documentManager.viewMode) { _, _ in
            EditorAppearanceSync.pushFocusMode()
            if let tabID = documentManager.selectedTabID {
                EditorWebViewPool.shared.activateTab(tabID, documentManager: documentManager)
            }
        }
    }

    private var activeTextBinding: Binding<String> {
        Binding(
            get: { textContent },
            set: { newValue in
                guard documentManager.selectedTabID != nil else { return }
                textContent = newValue
            }
        )
    }

    private func syncActiveTabContent() {
        suppressContentSync = true
        if let doc = documentManager.currentDocument, let tabID = documentManager.selectedTabID {
            documentManager.ensureUndoHistory(for: tabID, content: doc.content)
            textContent = doc.content
        } else {
            textContent = ""
        }
        suppressContentSync = false
    }
}

// MARK: - Editor Toolbar
struct EditorToolbar: View {
    @EnvironmentObject var documentManager: DocumentManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WrappingToolbarLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ToolbarButton(icon: "bold", tooltip: "Bold — wrap selection with ** (⌘B)") {
                    documentManager.toggleBold()
                }
                
                ToolbarButton(icon: "italic", tooltip: "Italic — wrap selection with * (⌘I)") {
                    documentManager.toggleItalic()
                }
                
                ToolbarButton(icon: "strikethrough", tooltip: "Strikethrough — wrap selection with ~~ (⌘⇧S)") {
                    documentManager.toggleStrikethrough()
                }
                
                ToolbarDivider()
                
                ToolbarHeadingMenu {
                    documentManager.insertHeading(level: $0)
                }
                
                ToolbarDivider()
                
                ToolbarButton(icon: "list.bullet", tooltip: "Bullet list — insert “- ” at line start") {
                    documentManager.insertBulletList()
                }
                
                ToolbarButton(icon: "list.number", tooltip: "Numbered list — insert “1. ” at line start") {
                    documentManager.insertNumberedList()
                }
                
                ToolbarButton(icon: "checklist", tooltip: "Task list — insert “- [ ] ” at line start") {
                    documentManager.insertTaskList()
                }
                
                ToolbarDivider()
                
                ToolbarButton(icon: "link", tooltip: "Insert link — [text](url) (⌘K)") {
                    documentManager.insertLink()
                }
                
                ToolbarButton(icon: "photo", tooltip: "Insert image from file or clipboard") {
                    documentManager.insertImage()
                }
                
                ToolbarButton(icon: "tablecells", tooltip: "Insert GFM table — choose rows and columns") {
                    documentManager.insertTable()
                }
                
                ToolbarButton(icon: "chevron.left.forwardslash.chevron.right", tooltip: "Insert fenced code block (⌘⇧`)") {
                    documentManager.insertCodeBlock()
                }
                
                ToolbarDivider()
                
                ToolbarButton(icon: "quote.opening", tooltip: "Blockquote — insert “> ” at line start") {
                    documentManager.insertBlockquote()
                }
                
                ToolbarButton(icon: "minus.forwardslash.plus", tooltip: "Horizontal rule — insert “---”") {
                    documentManager.insertHorizontalRule()
                }
            }
            
            if let doc = documentManager.currentDocument {
                WrappingToolbarLayout(horizontalSpacing: 12, verticalSpacing: 6) {
                    ToolbarStatLabel(icon: "text.alignleft", text: "\(doc.lineCount) lines")
                    ToolbarStatLabel(icon: "text.alignleft", text: "\(doc.wordCount) words")
                    ToolbarStatLabel(icon: "character", text: "\(doc.characterCount) chars")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToolbarDivider: View {
    var body: some View {
        Divider()
            .frame(width: 1, height: 20)
    }
}

private struct ToolbarStatLabel: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11))
        }
        .foregroundColor(.secondary)
    }
}

/// Переносит элементы тулбара на следующую строку при нехватке ширины.
private struct WrappingToolbarLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = result.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
            usedWidth = max(usedWidth, x - horizontalSpacing)
        }
        
        return (CGSize(width: usedWidth, height: y + rowHeight), positions)
    }
}

// MARK: - Toolbar Heading Menu
private struct ToolbarHeadingMenu: View {
    let onSelect: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(1...6, id: \.self) { level in
                Button("Heading \(level)") {
                    onSelect(level)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "textformat.size")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .frame(height: 24)
        .help("Heading — insert # … ###### at line start (H1–H6)")
        .background(ToolbarTooltipHost(message: "Heading — insert # … ###### at line start (H1–H6)"))
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .background(ToolbarTooltipHost(message: tooltip))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Native AppKit tooltip — надёжнее `.help` внутри custom Layout на macOS.
private struct ToolbarTooltipHost: NSViewRepresentable {
    let message: String

    func makeNSView(context: Context) -> TooltipHostView {
        let view = TooltipHostView()
        view.toolTip = message
        return view
    }

    func updateNSView(_ nsView: TooltipHostView, context: Context) {
        nsView.toolTip = message
    }
}

private final class TooltipHostView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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

// MARK: - Markdown Preview Area Правый экран с видимой маркдаун разметкой
struct MarkdownPreviewArea: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var themeService: ThemeService
    @AppStorage(AppConstants.Keys.showCodeLineNumbers) private var showCodeLineNumbers: Bool = false
    @AppStorage(AppConstants.Keys.previewSyncScroll) private var previewSyncScroll: Bool = true
    @Binding var editorScrollPosition: CGFloat
    
    var body: some View {
        Group {
            if let doc = documentManager.currentDocument {
                MarkdownRenderer(
                    markdown: doc.content,
                    documentURL: doc.url,
                    textColor: themeService.colors.text.description,
                    isDark: themeService.isDarkMode,
                    codeTheme: themeService.currentCodeTheme.rawValue,
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Outline")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    documentManager.requestOutlineHeadings(immediately: true)
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
                if documentManager.outlineHeadings.isEmpty {
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
                        ForEach(documentManager.outlineHeadings) { heading in
                            OutlineHeadingRow(heading: heading) {
                                documentManager.scrollToHeading(heading)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .background(themeService.currentTheme.colors.background)
        .foregroundStyle(themeService.currentTheme.colors.text)
        .onChange(of: documentManager.currentDocument?.content) { _, _ in
            documentManager.requestOutlineHeadings(immediately: false)
        }
        .onChange(of: documentManager.selectedTabID) { _, _ in
            documentManager.requestOutlineHeadings(immediately: true)
        }
        .onAppear {
            documentManager.requestOutlineHeadings(immediately: true)
        }
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
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
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
