//
//  FindReplacePanel.swift
//  Beardy2
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
            // Header
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                Text(showReplaceOptions ? "Find and Replace" : "Find")
                    .font(.headline)
                
                Spacer()
                
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
        .onAppear {
            isFindFieldFocused = true
            performFind()
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
    
    // MARK: - Find Methods
    private func performFind() {
        guard !findText.isEmpty else {
            matches = []
            matchCount = 0
            currentMatchIndex = 0
            return
        }
        
        matches = findAllMatches()
        matchCount = matches.count
        
        if matchCount > 0 {
            // Find closest match to current selection
            currentMatchIndex = findClosestMatch()
            highlightCurrentMatch()
        } else {
            currentMatchIndex = 0
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
        highlightCurrentMatch()
    }
    
    private func findPrevious() {
        guard matchCount > 0 else { return }
        
        currentMatchIndex = (currentMatchIndex - 1 + matchCount) % matchCount
        highlightCurrentMatch()
    }
    
    private func highlightCurrentMatch() {
        guard currentMatchIndex >= 0 && currentMatchIndex < matches.count else { return }
        
        selectedRange = matches[currentMatchIndex]
        
        // Post notification to scroll to selection
        NotificationCenter.default.post(
            name: .scrollToSelection,
            object: nil,
            userInfo: ["range": selectedRange]
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
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            if isPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isPresented = false
                    }
                
                FindReplacePanel(
                    isPresented: $isPresented,
                    textContent: $textContent,
                    selectedRange: $selectedRange
                )
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPresented)
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
    static let scrollToSelection = Notification.Name("scrollToSelection")
}

// MARK: - Preview
struct FindReplacePanel_Previews: PreviewProvider {
    static var previews: some View {
        FindReplacePanel(
            isPresented: .constant(true),
            textContent: .constant("Hello world! This is a test. Hello again!"),
            selectedRange: .constant(NSRange(location: 0, length: 0))
        )
    }
}
