import Foundation

struct EditorTab: Identifiable, Equatable {
    let id: UUID
    var document: MarkdownDocument

    init(id: UUID = UUID(), document: MarkdownDocument) {
        self.id = id
        self.document = document
    }

    static func == (lhs: EditorTab, rhs: EditorTab) -> Bool {
        lhs.id == rhs.id
    }
}
