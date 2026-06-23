import Combine
import Foundation

/// One WKWebView per tab: registration, targeted JS, flush, LRU eviction.
@MainActor
final class EditorWebViewPool {
    static let shared = EditorWebViewPool()

    private struct Handle {
        weak var coordinator: CodeMirrorWebView.Coordinator?
    }

    private var handles: [UUID: Handle] = [:]

    private init() {}

    func register(tabID: UUID, coordinator: CodeMirrorWebView.Coordinator) {
        handles[tabID] = Handle(coordinator: coordinator)
    }

    func unregister(tabID: UUID) {
        handles.removeValue(forKey: tabID)
    }

    func coordinator(for tabID: UUID) -> CodeMirrorWebView.Coordinator? {
        handles[tabID]?.coordinator
    }

    func handlesTarget(_ target: EditorExecTarget, activeTabID: UUID?) -> [CodeMirrorWebView.Coordinator] {
        switch target {
        case .allMounted:
            return handles.values.compactMap(\.coordinator)
        case .activeTab:
            guard let activeTabID, let c = coordinator(for: activeTabID) else { return [] }
            return [c]
        case .tab(let id):
            guard let c = coordinator(for: id) else { return [] }
            return [c]
        }
    }

    func exec(_ script: String, target: EditorExecTarget, activeTabID: UUID?) {
        for coordinator in handlesTarget(target, activeTabID: activeTabID) {
            coordinator.evaluateJS(script)
        }
    }

    func flushPendingSync(for tabID: UUID) {
        coordinator(for: tabID)?.evaluateJS("window.cmEditor?.prepareTabSwitch?.();")
    }

    func flushContent(
        for tabID: UUID,
        expectedGeneration: UInt = 1,
        fallback: String,
        completion: @escaping (String) -> Void
    ) {
        guard let coordinator = coordinator(for: tabID) else {
            completion(fallback)
            return
        }
        coordinator.flushEditorContent(expectedGeneration: expectedGeneration, fallback: fallback, completion: completion)
    }

    func pushContent(tabID: UUID, content: String) {
        coordinator(for: tabID)?.pushContentFromNative(content)
    }

    func activateTab(_ tabID: UUID, documentManager: DocumentManager) {
        guard let coordinator = coordinator(for: tabID) else { return }
        coordinator.syncForActivation(documentManager: documentManager)
        NotificationCenter.default.post(name: .editorTabDidBecomeActive, object: tabID)
    }

    func evictTab(_ tabID: UUID, fallbackContent: String) {
        if let coordinator = coordinator(for: tabID) {
            coordinator.evaluateJS("window.cmEditor?.prepareTabSwitch?.();")
            coordinator.evaluateJS("window.cmEditor?.suspendForTabEviction?.();")
        }
        unregister(tabID: tabID)
        DocumentManager.shared?.markTabEditorEvicted(tabID)
        _ = fallbackContent
    }
}

/// LRU warm WebView mount policy (lazy create, keep recent tabs alive).
@MainActor
final class TabWebViewMountState: ObservableObject {
    static let defaultWarmLimit = 5

    let warmLimit: Int
    @Published private(set) var warmOrder: [UUID] = []

    init(warmLimit: Int = TabWebViewMountState.defaultWarmLimit) {
        self.warmLimit = max(1, warmLimit)
    }

    func isWarm(_ id: UUID) -> Bool {
        warmOrder.contains(id)
    }

    func markVisited(_ id: UUID, documentManager: DocumentManager) {
        warmOrder.removeAll { $0 == id }
        warmOrder.append(id)
        while warmOrder.count > warmLimit {
            guard let evict = warmOrder.first, evict != id else { break }
            warmOrder.removeFirst()
            let content = documentManager.tabs.first(where: { $0.id == evict })?.document.content ?? ""
            EditorWebViewPool.shared.evictTab(evict, fallbackContent: content)
        }
    }

    func forget(_ id: UUID, documentManager: DocumentManager) {
        warmOrder.removeAll { $0 == id }
        let content = documentManager.tabs.first(where: { $0.id == id })?.document.content ?? ""
        EditorWebViewPool.shared.evictTab(id, fallbackContent: content)
    }

    func pruneClosedTabs(openTabIDs: Set<UUID>) {
        let removed = warmOrder.filter { !openTabIDs.contains($0) }
        warmOrder.removeAll { !openTabIDs.contains($0) }
        for id in removed {
            EditorWebViewPool.shared.unregister(tabID: id)
        }
    }

    /// Returns evicted tab id if capacity exceeded.
    @discardableResult
    private func touch(_ id: UUID) -> UUID? {
        warmOrder.removeAll { $0 == id }
        warmOrder.append(id)
        guard warmOrder.count > warmLimit else { return nil }
        let evict = warmOrder.removeFirst()
        if evict == id {
            warmOrder.append(id)
            return warmOrder.count > warmLimit ? warmOrder.removeFirst() : nil
        }
        return evict
    }
}
