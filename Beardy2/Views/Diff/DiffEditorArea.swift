import SwiftUI

struct DiffEditorArea: View {
    @EnvironmentObject private var documentManager: DocumentManager
    @EnvironmentObject private var themeService: ThemeService

    private var diff: DiffModeCoordinator { documentManager.diffCoordinator }

    private var diffViewIdentity: String {
        let sourceKey: String
        switch diff.comparisonSource {
        case .previousVersion:
            sourceKey = "auto"
        case .snapshot(let id):
            sourceKey = id.uuidString
        case .externalFile:
            sourceKey = diff.externalBaseline?.url.standardizedFileURL.path ?? "external"
        }
        return "\(documentManager.diffRenderRevision)-\(sourceKey)"
    }

    var body: some View {
        VStack(spacing: 0) {
            DiffToolbar()

            Divider()

            HStack(spacing: 0) {
                if let result = diff.diffResult {
                    DiffWebView(
                        html: result.html,
                        focusedChangeIndex: diff.currentChangeIndex
                    )
                    .id(diffViewIdentity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    DiffMinimap(
                        segments: result.minimapSegments,
                        currentChangeIndex: diff.currentChangeIndex,
                        onSelect: { documentManager.focusDiffChange($0) }
                    )
                    .id(diffViewIdentity)
                } else {
                    ContentUnavailableView(
                        "No comparison",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(
                            diff.placeholderMessage
                                ?? "Save the document (⌘S) to record a version, then compare changes here."
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if documentManager.viewMode == .diff {
                documentManager.reloadDiffModeForCurrentTab(resetSnapshotSelection: false)
            }
        }
        .onChange(of: documentManager.viewMode) { _, newMode in
            if newMode == .diff {
                documentManager.reloadDiffModeForCurrentTab(resetSnapshotSelection: false)
            }
        }
        .onChange(of: documentManager.selectedTabID) { _, _ in
            guard documentManager.viewMode == .diff else { return }
            documentManager.reloadDiffModeForCurrentTab(resetSnapshotSelection: false)
        }
        .onChange(of: themeService.appearanceToken) { _, _ in
            if documentManager.viewMode == .diff {
                documentManager.refreshDiffRender()
            }
        }
    }
}
