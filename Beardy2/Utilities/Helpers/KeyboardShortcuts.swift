import SwiftUI
import AppKit
import Combine

// MARK: - Keyboard Shortcuts Manager
class KeyboardShortcutsManager: ObservableObject {
    
    static let shared = KeyboardShortcutsManager()
    
    @Published var isEnabled: Bool = true
    private var eventMonitor: Any?
    
    private init() {
        setupGlobalShortcuts()
    }
    
    deinit {
        removeGlobalShortcuts()
    }
    
    // MARK: - Setup Global Shortcuts
    private func setupGlobalShortcuts() {
        // Monitor local keyboard events
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isEnabled else { return event }
            
            // Handle the event
            if self.handleKeyboardEvent(event) {
                return nil // Event handled, don't propagate
            }
            
            return event // Event not handled, propagate
        }
    }
    
    private func removeGlobalShortcuts() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    // MARK: - Handle Keyboard Event
    private func handleKeyboardEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
        let keyCode = event.keyCode
        let characters = event.charactersIgnoringModifiers ?? ""
        
        // Command key shortcuts
        if modifiers.contains(.command) {
            return handleCommandShortcuts(characters: characters, modifiers: modifiers, event: event)
        }
        
        return false
    }
    
    // MARK: - Command Shortcuts
    private func handleCommandShortcuts(characters: String, modifiers: NSEvent.ModifierFlags, event: NSEvent) -> Bool {
        
        // Get document manager
        guard let documentManager = getDocumentManager() else { return false }
        
        let hasShift = modifiers.contains(.shift)
        let hasOption = modifiers.contains(.option)
        
        switch characters.lowercased() {
            
        // File operations
        case "n" where !hasShift && !hasOption:
            documentManager.createNewDocument()
            return true
            
        case "o" where !hasShift && !hasOption:
            documentManager.openDocument()
            return true
            
        case "s" where !hasShift && !hasOption:
            documentManager.saveDocument()
            return true
            
        case "s" where hasShift && !hasOption:
            documentManager.saveDocumentAs()
            return true
            
        case "e" where !hasShift && !hasOption:
            documentManager.exportAsPDF()
            return true
            
        // Edit operations (handled by system, but we can add custom behavior)
        case "f" where !hasShift && !hasOption:
            documentManager.showFindPanel()
            return true
            
        case "f" where !hasShift && hasOption:
            documentManager.showReplacePanel()
            return true
            
        // Formatting
        case "b" where !hasShift && !hasOption:
            documentManager.toggleBold()
            return true
            
        case "i" where !hasShift && !hasOption:
            documentManager.toggleItalic()
            return true
            
        case "`" where !hasShift && !hasOption:
            documentManager.toggleInlineCode()
            return true
            
        case "`" where hasShift && !hasOption:
            documentManager.insertCodeBlock()
            return true
            
        case "k" where !hasShift && !hasOption:
            documentManager.insertLink()
            return true
            
        case "i" where hasShift && !hasOption:
            documentManager.insertImage()
            return true
            
        // Headings
        case "1" where !hasShift && !hasOption:
            documentManager.insertHeading(level: 1)
            return true
        case "2" where !hasShift && !hasOption:
            documentManager.insertHeading(level: 2)
            return true
        case "3" where !hasShift && !hasOption:
            documentManager.insertHeading(level: 3)
            return true
        case "4" where !hasShift && !hasOption:
            documentManager.insertHeading(level: 4)
            return true
        case "5" where !hasShift && !hasOption:
            documentManager.insertHeading(level: 5)
            return true
        case "6" where !hasShift && !hasOption:
            documentManager.insertHeading(level: 6)
            return true
            
        // View
        case "\\" where !hasShift && !hasOption:
            documentManager.toggleSidebar()
            return true
            
        case "/" where !hasShift && !hasOption:
            documentManager.toggleSourceMode()
            return true
            
        case "f" where hasShift && !hasOption:
            documentManager.toggleFocusMode()
            return true
            
        case "t" where hasShift && !hasOption:
            documentManager.toggleTypewriterMode()
            return true
            
        default:
            return false
        }
    }
    
    // MARK: - Get Document Manager
    private func getDocumentManager() -> DocumentManager? {
        // Use the shared singleton reference set during app initialization
        return DocumentManager.shared
    }
}

// MARK: - Keyboard Shortcut View Modifier
struct KeyboardShortcutHandler: ViewModifier {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                Button("") {
                    action()
                }
                .keyboardShortcut(key, modifiers: modifiers)
                .hidden()
            )
    }
}

extension View {
    func onKeyboardShortcut(
        _ key: KeyEquivalent,
        modifiers: EventModifiers = .command,
        perform action: @escaping () -> Void
    ) -> some View {
        modifier(KeyboardShortcutHandler(key: key, modifiers: modifiers, action: action))
    }
}

// MARK: - Shortcuts Help Panel
struct ShortcutsHelpPanel: View {
    @Environment(\.dismiss) var dismiss
    
    let shortcuts: [(category: String, items: [(shortcut: String, description: String)])] = [
        ("File", [
            ("⌘N", "New Document"),
            ("⌘O", "Open Document"),
            ("⌘S", "Save Document"),
            ("⇧⌘S", "Save As"),
            ("⌘E", "Export as PDF"),
            ("⌘W", "Close Window"),
            ("⌘Q", "Quit")
        ]),
        ("Edit", [
            ("⌘Z", "Undo"),
            ("⇧⌘Z", "Redo"),
            ("⌘X", "Cut"),
            ("⌘C", "Copy"),
            ("⌘V", "Paste"),
            ("⌘A", "Select All"),
            ("⌘F", "Find"),
            ("⌥⌘F", "Find and Replace")
        ]),
        ("Format", [
            ("⌘B", "Bold"),
            ("⌘I", "Italic"),
            ("⌘U", "Underline"),
            ("⇧⌘S", "Strikethrough"),
            ("⌘`", "Inline Code"),
            ("⇧⌘`", "Code Block"),
            ("⌘K", "Insert Link"),
            ("⇧⌘I", "Insert Image")
        ]),
        ("Headings", [
            ("⌘1", "Heading 1"),
            ("⌘2", "Heading 2"),
            ("⌘3", "Heading 3"),
            ("⌘4", "Heading 4"),
            ("⌘5", "Heading 5"),
            ("⌘6", "Heading 6")
        ]),
        ("View", [
            ("⌘\\", "Toggle Sidebar"),
            ("⌘/", "Toggle Source Mode"),
            ("⇧⌘F", "Focus Mode"),
            ("⇧⌘T", "Typewriter Mode"),
            ("⌘0", "Actual Size"),
            ("⌘+", "Zoom In"),
            ("⌘-", "Zoom Out")
        ]),
        ("Other", [
            ("⌘,", "Preferences"),
            ("⌘?", "Show Shortcuts"),
            ("Esc", "Cancel")
        ])
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Shortcuts List
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(shortcuts, id: \.category) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.category)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 8) {
                                ForEach(section.items, id: \.shortcut) { item in
                                    ShortcutRow(
                                        shortcut: item.shortcut,
                                        description: item.description
                                    )
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
        }
        .frame(width: 600, height: 700)
    }
}

struct ShortcutRow: View {
    let shortcut: String
    let description: String
    
    var body: some View {
        HStack {
            Text(description)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(shortcut)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
        }
    }
}

// MARK: - Show Shortcuts Button
struct ShowShortcutsButton: View {
    @State private var showShortcuts = false
    
    var body: some View {
        Button(action: {
            showShortcuts = true
        }) {
            Image(systemName: "keyboard")
        }
        .help("Show Keyboard Shortcuts (⌘?)")
        .sheet(isPresented: $showShortcuts) {
            ShortcutsHelpPanel()
        }
    }
}

struct ShortcutsHelpPanel_Previews: PreviewProvider {
    static var previews: some View {
        ShortcutsHelpPanel()
    }
}
