//
//  FindReplacePanel.swift
//  BlackBeardEditor
//
//  Created by Butt Simpson on 30.12.2025.
//

import SwiftUI
import AppKit

// MARK: - Find Replace Panel
struct FindReplacePanel: View {
    @Binding var isPresented: Bool
    @Binding var textContent: String
    @Binding var selectedRange: NSRange
    var baseOffset: CGSize = .zero
    @Binding var liveDragOffset: CGSize
    var onDragEnded: (CGSize) -> Void = { _ in }
    
    @State private var findText: String = ""
    @State private var replaceText: String = ""
    @State private var isCaseSensitive: Bool = false
    @State private var isWholeWord: Bool = false
    @State private var useRegex: Bool = false
    @State private var matchCount: Int = 0
    @State private var currentMatchIndex: Int = 0
    @State private var matches: [NSRange] = []
    @State private var showReplaceOptions: Bool = false
    
    @FocusState private var isFindFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (drag handle)
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Drag to move")

                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    Text(showReplaceOptions ? "Find and Replace" : "Find")
                        .font(.headline)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(panelDragGesture)
                .onHover { hovering in
                    if hovering {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                // Toggle replace options
                Button(action: {
                    withAnimation {
                        showReplaceOptions.toggle()
                    }
                }) {
                    Image(systemName: showReplaceOptions ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(showReplaceOptions ? "Hide Replace" : "Show Replace")

                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Find field
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    TextField("Find", text: $findText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFindFieldFocused)
                        .onSubmit {
                            findNext()
                        }
                    
                    // Match counter
                    if !findText.isEmpty {
                        Text(matchCount > 0 ? "\(currentMatchIndex + 1) of \(matchCount)" : "No matches")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 80)
                    }
                    
                    // Navigation buttons
                    HStack(spacing: 4) {
                        Button(action: findPrevious) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .disabled(matchCount == 0)
                        .help("Previous (⇧⌘G)")
                        
                        Button(action: findNext) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .disabled(matchCount == 0)
                        .help("Next (⌘G)")
                    }
                }
                
                // Replace field (shown when toggled)
                if showReplaceOptions {
                    HStack(spacing: 8) {
                        TextField("Replace", text: $replaceText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                replaceCurrent()
                            }
                        
                        HStack(spacing: 4) {
                            Button("Replace") {
                                replaceCurrent()
                            }
                            .buttonStyle(.bordered)
                            .disabled(matchCount == 0)
                            
                            Button("Replace All") {
                                replaceAll()
                            }
                            .buttonStyle(.bordered)
                            .disabled(matchCount == 0)
                        }
                    }
                }
                
                // Options
                HStack(spacing: 16) {
                    Toggle("Case Sensitive", isOn: $isCaseSensitive)
                        .font(.caption)
                    
                    Toggle("Whole Word", isOn: $isWholeWord)
                        .font(.caption)
                    
                    Toggle("Regex", isOn: $useRegex)
                        .font(.caption)
                    
                    Spacer()
                }
                .toggleStyle(.checkbox)
            }
            .padding()
        }
        .frame(width: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 10)
        .offset(
            x: baseOffset.width + liveDragOffset.width,
            y: baseOffset.height + liveDragOffset.height
        )
        .onAppear {
            isFindFieldFocused = true
            performFind()
        }
        .onDisappear {
            NotificationCenter.default.post(
                name: .editorFindDidUpdate,
                object: nil,
                userInfo: ["active": false]
            )
        }
        .onChange(of: findText) { _, _ in
            performFind()
        }
        .onChange(of: isCaseSensitive) { _, _ in
            performFind()
        }
        .onChange(of: isWholeWord) { _, _ in
            performFind()
        }
        .onChange(of: useRegex) { _, _ in
            performFind()
        }
    }

    private var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                liveDragOffset = value.translation
            }
            .onEnded { value in
                onDragEnded(value.translation)
                liveDragOffset = .zero
            }
    }
    
    // MARK: - Find Methods
    private func performFind() {
        guard !findText.isEmpty else {
            matches = []
            matchCount = 0
            currentMatchIndex = 0
            publishFindState(clear: true)
            return
        }
        
        matches = findAllMatches()
        matchCount = matches.count
        
        if matchCount > 0 {
            // Find closest match to current selection
            currentMatchIndex = findClosestMatch()
            publishFindState()
        } else {
            currentMatchIndex = 0
            publishFindState(clear: true)
        }
    }
    
    private func findAllMatches() -> [NSRange] {
        var foundRanges: [NSRange] = []
        
        if useRegex {
            // Regex search
            do {
                let options: NSRegularExpression.Options = isCaseSensitive ? [] : .caseInsensitive
                let regex = try NSRegularExpression(pattern: findText, options: options)
                let nsString = textContent as NSString
                let matches = regex.matches(in: textContent, options: [], range: NSRange(location: 0, length: nsString.length))
                foundRanges = matches.map { $0.range }
            } catch {
                print("Invalid regex: \(error)")
            }
        } else {
            // Plain text search
            var searchOptions: String.CompareOptions = []
            if !isCaseSensitive {
                searchOptions.insert(.caseInsensitive)
            }
            if isWholeWord {
                // Implement whole word matching
                let words = textContent.components(separatedBy: .whitespacesAndNewlines)
                var currentIndex = 0
                
                for word in words {
                    if word.compare(findText, options: searchOptions) == .orderedSame {
                        let range = NSRange(location: currentIndex, length: word.count)
                        foundRanges.append(range)
                    }
                    currentIndex += word.count + 1
                }
            } else {
                var searchRange = textContent.startIndex..<textContent.endIndex
                
                while let range = textContent.range(of: findText, options: searchOptions, range: searchRange) {
                    let nsRange = NSRange(range, in: textContent)
                    foundRanges.append(nsRange)
                    searchRange = range.upperBound..<textContent.endIndex
                }
            }
        }
        
        return foundRanges
    }
    
    private func findClosestMatch() -> Int {
        guard !matches.isEmpty else { return 0 }
        
        // Find match closest to current selection
        let currentLocation = selectedRange.location
        
        for (index, match) in matches.enumerated() {
            if match.location >= currentLocation {
                return index
            }
        }
        
        return 0
    }
    
    private func findNext() {
        guard matchCount > 0 else { return }
        
        currentMatchIndex = (currentMatchIndex + 1) % matchCount
        publishFindState()
    }
    
    private func findPrevious() {
        guard matchCount > 0 else { return }
        
        currentMatchIndex = (currentMatchIndex - 1 + matchCount) % matchCount
        publishFindState()
    }
    
    private func publishFindState(clear: Bool = false) {
        if clear || findText.isEmpty || matches.isEmpty {
            NotificationCenter.default.post(
                name: .editorFindDidUpdate,
                object: nil,
                userInfo: ["active": false]
            )
            return
        }
        
        guard currentMatchIndex >= 0, currentMatchIndex < matches.count else { return }
        
        let current = matches[currentMatchIndex]
        selectedRange = current
        
        let rangePayload = matches.map { range in
            ["location": range.location, "length": range.length]
        }
        
        NotificationCenter.default.post(
            name: .editorFindDidUpdate,
            object: nil,
            userInfo: [
                "active": true,
                "query": findText,
                "ranges": rangePayload,
                "currentIndex": currentMatchIndex,
                "caseSensitive": isCaseSensitive
            ]
        )
    }
    
    // MARK: - Replace Methods
    private func replaceCurrent() {
        guard matchCount > 0,
              currentMatchIndex >= 0,
              currentMatchIndex < matches.count else { return }
        
        let matchRange = matches[currentMatchIndex]
        
        // Replace text
        let nsString = textContent as NSString
        textContent = nsString.replacingCharacters(in: matchRange, with: replaceText)
        
        // Update matches
        performFind()
        
        // Move to next match
        if matchCount > 0 {
            findNext()
        }
    }
    
    private func replaceAll() {
        guard matchCount > 0 else { return }
        
        var offset = 0
        let sortedMatches = matches.sorted { $0.location < $1.location }
        
        var newText = textContent
        
        for match in sortedMatches {
            let adjustedRange = NSRange(
                location: match.location + offset,
                length: match.length
            )
            
            let nsString = newText as NSString
            newText = nsString.replacingCharacters(in: adjustedRange, with: replaceText)
            
            offset += replaceText.count - match.length
        }
        
        textContent = newText
        
        // Update matches
        performFind()
    }
}

// MARK: - Find Replace Overlay
struct FindReplaceOverlay: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var textContent: String
    @Binding var selectedRange: NSRange

    @AppStorage("findPanelOffsetX") private var offsetX: Double = 0
    @AppStorage("findPanelOffsetY") private var offsetY: Double = 60
    @State private var liveDragOffset: CGSize = .zero
    @State private var containerSize: CGSize = .zero

    private let panelSize = CGSize(width: 500, height: 220)

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { containerSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in
                            containerSize = newSize
                        }
                }
            }
            .overlay(alignment: .top) {
                if isPresented {
                    FindReplacePanel(
                        isPresented: $isPresented,
                        textContent: $textContent,
                        selectedRange: $selectedRange,
                        baseOffset: storedOffset,
                        liveDragOffset: $liveDragOffset,
                        onDragEnded: { translation in
                            let next = clampedOffset(
                                CGSize(
                                    width: storedOffset.width + translation.width,
                                    height: storedOffset.height + translation.height
                                ),
                                in: containerSize
                            )
                            offsetX = next.width
                            offsetY = next.height
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(20)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPresented)
            .onChange(of: isPresented) { _, visible in
                if !visible {
                    NotificationCenter.default.post(
                        name: .editorFindDidUpdate,
                        object: nil,
                        userInfo: ["active": false]
                    )
                }
            }
    }

    private var storedOffset: CGSize {
        CGSize(width: offsetX, height: offsetY)
    }

    private func clampedOffset(_ proposed: CGSize, in container: CGSize) -> CGSize {
        let horizontalPadding: CGFloat = 16
        let minY: CGFloat = 12
        let maxY = max(minY, container.height - panelSize.height - 12)
        let maxX = max(0, (container.width - panelSize.width) / 2 - horizontalPadding)
        let minX = -maxX

        return CGSize(
            width: min(max(proposed.width, minX), maxX),
            height: min(max(proposed.height, minY), maxY)
        )
    }
}

extension View {
    func findReplacePanel(
        isPresented: Binding<Bool>,
        textContent: Binding<String>,
        selectedRange: Binding<NSRange>
    ) -> some View {
        modifier(FindReplaceOverlay(
            isPresented: isPresented,
            textContent: textContent,
            selectedRange: selectedRange
        ))
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let editorFindDidUpdate = Notification.Name("editorFindDidUpdate")
}

// MARK: - Preview
struct FindReplacePanel_Previews: PreviewProvider {
    static var previews: some View {
        FindReplacePanel(
            isPresented: .constant(true),
            textContent: .constant("Hello world! This is a test. Hello again!"),
            selectedRange: .constant(NSRange(location: 0, length: 0)),
            liveDragOffset: .constant(.zero)
        )
    }
}
