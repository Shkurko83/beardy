import Foundation

/// Tracks which tab the shared WebView is allowed to read/write.
struct EditorPresentationState: Equatable {
    var tabID: UUID?
    var generation: UInt = 0
    /// WebView finished loading `tabID` for `generation`.
    var isReady: Bool = false

    var isReadyForSelectedTab: Bool {
        guard isReady, let tabID else { return false }
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
