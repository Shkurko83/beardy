import Foundation

/// Tracks which tab the shared WebView is allowed to read/write.
struct EditorPresentationState: Equatable {
    var tabID: UUID?
    var generation: UInt = 0
    /// WebView finished loading `tabID` for `generation`.
    var isReady: Bool = false
    /// Character count Swift pushed for the active session (integrity check).
    var expectedCharacterCount: Int = 0

    var isReadyForSelectedTab: Bool {
        guard isReady, tabID != nil else { return false }
        return true
    }
}

struct EditorContentMessage: Equatable {
    let tabID: UUID
    let generation: UInt
    let content: String
}

enum EditorContentDeliverySource {
    case userEdit
    case documentLoaded
    case flush
}

struct EditorFlushMessage: Equatable {
    let tabID: UUID
    let generation: UInt
    let content: String
}
