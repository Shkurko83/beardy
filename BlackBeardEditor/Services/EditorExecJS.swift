import Foundation

enum EditorExecTarget: Equatable {
    case activeTab
    case allMounted
    case tab(UUID)
}

struct EditorExecJSPayload {
    let script: String
    let target: EditorExecTarget

    static func from(_ notification: Notification) -> EditorExecJSPayload? {
        if let payload = notification.object as? EditorExecJSPayload {
            return payload
        }
        if let script = notification.object as? String {
            return EditorExecJSPayload(script: script, target: .activeTab)
        }
        return nil
    }
}

enum EditorExecJS {
    static func post(_ script: String, target: EditorExecTarget = .activeTab) {
        NotificationCenter.default.post(
            name: .editorExecJS,
            object: EditorExecJSPayload(script: script, target: target)
        )
    }
}

extension Notification.Name {
    static let editorTabDidClose = Notification.Name("editorTabDidClose")
    static let editorTabDidBecomeActive = Notification.Name("editorTabDidBecomeActive")
}
