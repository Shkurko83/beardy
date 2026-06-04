import Foundation

/// Per-tab Diff comparison settings (comparison file, snapshot, external baseline).
struct TabDiffSettings: Equatable {
    var comparisonSource: DiffComparisonSource = .previousVersion
    var selectedSnapshotID: UUID?
    var externalBaseline: ExternalDiffBaseline?
}
