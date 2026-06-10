import Foundation
import Combine

enum DiffComparisonSource: Equatable {
    /// Newest stored version that differs from the current editor text.
    case previousVersion
    case snapshot(UUID)
    case externalFile
}

struct ExternalDiffBaseline: Equatable {
    let url: URL
    let fileName: String
    let content: String
}

/// State for Diff Mode (paired with `ViewMode.diff`).
final class DiffModeCoordinator: ObservableObject {
    @Published var comparisonSource: DiffComparisonSource = .previousVersion
    @Published var selectedSnapshotID: UUID?
    @Published var externalBaseline: ExternalDiffBaseline?
    @Published var currentChangeIndex: Int = 1
    @Published var totalChanges: Int = 0
    @Published var granularity: DiffGranularity = .word
    @Published var snapshots: [DocumentSnapshot] = []
    @Published var diffResult: DiffRenderResult?
    @Published var placeholderMessage: String?

    var previousMode: ViewMode = .preview
    var isActive: Bool = false

    func resetNavigation(changeCount: Int) {
        totalChanges = changeCount
        currentChangeIndex = changeCount > 0 ? 1 : 0
    }

    func clearExternalBaseline() {
        externalBaseline = nil
        if comparisonSource == .externalFile {
            comparisonSource = .previousVersion
        }
    }
}
