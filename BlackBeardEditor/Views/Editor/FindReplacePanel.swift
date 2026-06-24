//
//  FindReplacePanel.swift
//  BlackBeardEditor
//

import SwiftUI
import AppKit

// MARK: - Find window (separate movable window, like Settings)

struct FindReplaceWindowView: View {
    @EnvironmentObject private var documentManager: DocumentManager

    var body: some View {
        FindReplacePanel(showReplaceOnOpen: documentManager.findPanelShowsReplace)
            .frame(minWidth: 500)
            .padding(.top, 4)
    }
}

// MARK: - Find Replace Panel

struct FindReplacePanel: View {
    @EnvironmentObject private var documentManager: DocumentManager
    var showReplaceOnOpen: Bool = false

    @State private var findText: String = ""
    @State private var replaceText: String = ""
    @State private var isCaseSensitive: Bool = false
    @State private var isWholeWord: Bool = false
    @State private var useRegex: Bool = false
    @State private var matchCount: Int = 0
    @State private var currentMatchIndex: Int = 0
    @State private var matches: [NSRange] = []
    @State private var showReplaceOptions: Bool = false
    @State private var selectedRange = NSRange(location: 0, length: 0)

    @FocusState private var isFindFieldFocused: Bool

    private var hasSearchableDocument: Bool {
        documentManager.hasOpenTabs && documentManager.currentDocument != nil
    }

    private var searchableContent: String {
        documentManager.currentDocument?.content ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                Text(showReplaceOptions ? "Find and Replace" : "Find")
                    .font(.headline)

                Spacer(minLength: 0)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showReplaceOptions.toggle()
                    }
                }) {
                    Image(systemName: showReplaceOptions ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(showReplaceOptions ? "Hide Replace" : "Show Replace")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            VStack(spacing: 12) {
                if !hasSearchableDocument {
                    Text("Open a document to search.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    TextField("Find", text: $findText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFindFieldFocused)
                        .disabled(!hasSearchableDocument)
                        .onSubmit { findNext() }

                    if !findText.isEmpty {
                        Text(matchCount > 0 ? "\(currentMatchIndex + 1) of \(matchCount)" : "No matches")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 80)
                    }

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

                if showReplaceOptions {
                    HStack(spacing: 8) {
                        TextField("Replace", text: $replaceText)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!hasSearchableDocument)
                            .onSubmit { replaceCurrent() }

                        HStack(spacing: 4) {
                            Button("Replace") { replaceCurrent() }
                                .buttonStyle(.bordered)
                                .disabled(matchCount == 0)

                            Button("Replace All") { replaceAll() }
                                .buttonStyle(.bordered)
                                .disabled(matchCount == 0)
                        }
                    }
                }

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
        .onAppear {
            if showReplaceOnOpen {
                showReplaceOptions = true
            }
            isFindFieldFocused = true
            performFind()
        }
        .onDisappear {
            clearFindHighlights()
        }
        .onChange(of: findText) { _, _ in performFind() }
        .onChange(of: isCaseSensitive) { _, _ in performFind() }
        .onChange(of: isWholeWord) { _, _ in performFind() }
        .onChange(of: useRegex) { _, _ in performFind() }
        .onChange(of: documentManager.currentDocument?.content) { _, _ in
            if !findText.isEmpty {
                performFind()
            }
        }
        .onChange(of: documentManager.selectedTabID) { _, _ in
            if !findText.isEmpty {
                performFind()
            } else {
                clearFindHighlights()
            }
        }
    }

    // MARK: - Find

    private func performFind() {
        guard hasSearchableDocument, !findText.isEmpty else {
            matches = []
            matchCount = 0
            currentMatchIndex = 0
            publishFindState(clear: true)
            return
        }

        matches = findAllMatches()
        matchCount = matches.count

        if matchCount > 0 {
            currentMatchIndex = findClosestMatch()
            publishFindState()
        } else {
            currentMatchIndex = 0
            publishFindState(clear: true)
        }
    }

    private func findAllMatches() -> [NSRange] {
        let textContent = searchableContent
        var foundRanges: [NSRange] = []

        if useRegex {
            do {
                let options: NSRegularExpression.Options = isCaseSensitive ? [] : .caseInsensitive
                let regex = try NSRegularExpression(pattern: findText, options: options)
                let nsString = textContent as NSString
                foundRanges = regex.matches(
                    in: textContent,
                    options: [],
                    range: NSRange(location: 0, length: nsString.length)
                ).map(\.range)
            } catch {
                print("Invalid regex: \(error)")
            }
        } else {
            var searchOptions: String.CompareOptions = []
            if !isCaseSensitive {
                searchOptions.insert(.caseInsensitive)
            }
            if isWholeWord {
                let words = textContent.components(separatedBy: .whitespacesAndNewlines)
                var currentIndex = 0
                for word in words {
                    if word.compare(findText, options: searchOptions) == .orderedSame {
                        foundRanges.append(NSRange(location: currentIndex, length: word.count))
                    }
                    currentIndex += word.count + 1
                }
            } else {
                var searchRange = textContent.startIndex..<textContent.endIndex
                while let range = textContent.range(of: findText, options: searchOptions, range: searchRange) {
                    foundRanges.append(NSRange(range, in: textContent))
                    searchRange = range.upperBound..<textContent.endIndex
                }
            }
        }

        return foundRanges
    }

    private func findClosestMatch() -> Int {
        guard !matches.isEmpty else { return 0 }
        let currentLocation = selectedRange.location
        for (index, match) in matches.enumerated() where match.location >= currentLocation {
            return index
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
            clearFindHighlights()
            return
        }

        guard currentMatchIndex >= 0, currentMatchIndex < matches.count else { return }

        let current = matches[currentMatchIndex]
        selectedRange = current

        let rangePayload = matches.map { ["location": $0.location, "length": $0.length] }

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

    private func clearFindHighlights() {
        NotificationCenter.default.post(
            name: .editorFindDidUpdate,
            object: nil,
            userInfo: ["active": false]
        )
    }

    // MARK: - Replace

    private func applyContentToDocument(_ newText: String) {
        documentManager.updateContent(newText)
        if let tabID = documentManager.selectedTabID {
            EditorWebViewPool.shared.pushContent(tabID: tabID, content: newText)
        }
    }

    private func replaceCurrent() {
        guard matchCount > 0,
              currentMatchIndex >= 0,
              currentMatchIndex < matches.count else { return }

        let textContent = searchableContent
        let matchRange = matches[currentMatchIndex]
        let newText = (textContent as NSString).replacingCharacters(in: matchRange, with: replaceText)
        applyContentToDocument(newText)
        performFind()
        if matchCount > 0 {
            findNext()
        }
    }

    private func replaceAll() {
        guard matchCount > 0 else { return }

        var offset = 0
        var newText = searchableContent
        for match in matches.sorted(by: { $0.location < $1.location }) {
            let adjustedRange = NSRange(location: match.location + offset, length: match.length)
            newText = (newText as NSString).replacingCharacters(in: adjustedRange, with: replaceText)
            offset += replaceText.count - match.length
        }
        applyContentToDocument(newText)
        performFind()
    }
}

extension Notification.Name {
    static let editorFindDidUpdate = Notification.Name("editorFindDidUpdate")
}

#if DEBUG
struct FindReplacePanel_Previews: PreviewProvider {
    static var previews: some View {
        FindReplacePanel()
            .environmentObject(DocumentManager())
            .padding()
    }
}
#endif
