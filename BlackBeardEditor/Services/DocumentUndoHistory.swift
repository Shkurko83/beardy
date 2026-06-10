//
//  DocumentUndoHistory.swift
//  BlackBeardEditor
//

import Foundation

/// Per-document undo/redo stack over full markdown source (Typora-style grouping).
struct DocumentUndoHistory: Equatable {
    private(set) var states: [String] = []
    private(set) var index: Int = 0
    private var groupDeadline: Date?
    private let groupingInterval: TimeInterval = 0.85
    private let maxStates = 200

    var canUndo: Bool { index > 0 }
    var canRedo: Bool { index < states.count - 1 }

    mutating func reset(with content: String) {
        states = [content]
        index = 0
        groupDeadline = nil
    }

    mutating func replaceCurrent(with content: String) {
        guard states.indices.contains(index) else { return }
        states[index] = content
    }

    mutating func record(content: String, forceNewGroup: Bool = false) {
        guard !states.isEmpty else {
            reset(with: content)
            return
        }
        guard states[index] != content else { return }

        let now = Date()
        let canGroup = !forceNewGroup
            && groupDeadline != nil
            && now < (groupDeadline ?? .distantPast)

        if canGroup {
            states[index] = content
        } else {
            states = Array(states.prefix(index + 1))
            states.append(content)
            index = states.count - 1
            trimIfNeeded()
        }
        groupDeadline = now.addingTimeInterval(groupingInterval)
    }

    mutating func undo() -> String? {
        guard canUndo else { return nil }
        index -= 1
        groupDeadline = nil
        return states[index]
    }

    mutating func redo() -> String? {
        guard canRedo else { return nil }
        index += 1
        groupDeadline = nil
        return states[index]
    }

    private mutating func trimIfNeeded() {
        guard states.count > maxStates else { return }
        let overflow = states.count - maxStates
        states.removeFirst(overflow)
        index = max(0, index - overflow)
    }
}
