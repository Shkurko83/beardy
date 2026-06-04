import Foundation

struct DocumentSnapshot: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let content: String
    let label: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        content: String,
        label: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.content = content
        self.label = label
    }

    var displayTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let datePart = formatter.string(from: createdAt)
        if let label, !label.isEmpty {
            return "\(datePart) — \(label)"
        }
        return datePart
    }
}

struct SnapshotFile: Codable {
    var documentPath: String
    var snapshots: [DocumentSnapshot]
}

struct DiffChunk: Identifiable, Equatable {
    enum Kind: Equatable {
        case equal
        case inserted
        case deleted
        case blockDeleted
        case blockInserted
    }

    let id = UUID()
    let kind: Kind
    let text: String
    let renderedHTML: String?
    /// 1-based index among change chunks (non-equal); nil for equal spans.
    let changeIndex: Int?
    /// Stable block position in the diff walk (same for word and block granularity).
    let blockOrdinal: Int?

    var isChange: Bool {
        switch kind {
        case .equal: return false
        default: return true
        }
    }
}

enum DiffGranularity: String, CaseIterable, Identifiable {
    case word
    case block

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .word: return "Word"
        case .block: return "Block"
        }
    }
}

struct DiffRenderResult: Equatable {
    let html: String
    let changeCount: Int
    /// Normalized vertical positions 0...1 for minimap segments.
    let minimapSegments: [DiffMinimapSegment]
}

struct DiffMinimapSegment: Identifiable, Equatable {
    let id: Int
    let start: CGFloat
    let length: CGFloat
    let isInsertion: Bool
}
