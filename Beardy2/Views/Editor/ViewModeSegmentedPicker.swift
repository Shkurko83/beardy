//
//  ViewModeSegmentedPicker.swift
//  Beardy2
//

import AppKit
import SwiftUI

extension ViewMode {
    var tooltip: String {
        switch self {
        case .edit:
            return "Edit — write markdown source as plain text"
        case .live:
            return "Live — edit rendered blocks inline (WYSIWYG style)"
        case .preview:
            return "Preview — read-only rendered document"
        case .split:
            return "Split — source editor and preview side by side"
        case .diff:
            return "Diff — compare current document with a saved version (read-only)"
        }
    }

    fileprivate var segmentLabel: String {
        switch self {
        case .edit: return "Edit"
        case .live: return "Live"
        case .preview: return "Preview"
        case .split: return "Split"
        case .diff: return "Diff"
        }
    }

    fileprivate var segmentSymbol: String {
        switch self {
        case .edit: return "pencil"
        case .live: return "doc.richtext"
        case .preview: return "eye"
        case .split: return "rectangle.split.2x1"
        case .diff: return "arrow.left.arrow.right"
        }
    }
}

/// Segmented control with a separate tooltip for each view mode (macOS `.help` on Picker does not).
struct ViewModeSegmentedPicker: NSViewRepresentable {
    @Binding var selection: ViewMode

    private static let segmentModes: [ViewMode] = [.edit, .live, .preview, .split, .diff]

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: Self.segmentModes.map(\.segmentLabel),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.segmentChanged(_:))
        )
        control.segmentStyle = .automatic
        control.controlSize = .regular

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        for (index, mode) in Self.segmentModes.enumerated() {
            if let image = NSImage(systemSymbolName: mode.segmentSymbol, accessibilityDescription: mode.segmentLabel)?
                .withSymbolConfiguration(symbolConfig) {
                image.isTemplate = true
                control.setImage(image, forSegment: index)
            }
            control.setLabel(mode.segmentLabel, forSegment: index)
            control.setToolTip(mode.tooltip, forSegment: index)
        }

        control.selectedSegment = Self.index(for: selection)
        context.coordinator.control = control
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        let targetIndex = Self.index(for: selection)
        if control.selectedSegment != targetIndex {
            control.selectedSegment = targetIndex
        }
    }

    private static func index(for mode: ViewMode) -> Int {
        segmentModes.firstIndex(of: mode) ?? 0
    }

    final class Coordinator: NSObject {
        var selection: Binding<ViewMode>
        weak var control: NSSegmentedControl?

        init(selection: Binding<ViewMode>) {
            self.selection = selection
        }

        @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard index >= 0, index < ViewModeSegmentedPicker.segmentModes.count else { return }
            selection.wrappedValue = ViewModeSegmentedPicker.segmentModes[index]
        }
    }
}
