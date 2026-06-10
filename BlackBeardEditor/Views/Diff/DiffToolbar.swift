import SwiftUI

struct DiffToolbar: View {
    @EnvironmentObject private var documentManager: DocumentManager
    @EnvironmentObject private var themeService: ThemeService

    private var diff: DiffModeCoordinator { documentManager.diffCoordinator }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { documentManager.diffPreviousChange() }) {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(diff.totalChanges == 0)
            .help("Previous change (P)")

            Text(changeCounterText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(themeService.currentTheme.colors.secondaryText)
                .frame(minWidth: 100)

            Button(action: { documentManager.diffNextChange() }) {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(diff.totalChanges == 0)
            .help("Next change (N)")

            Divider().frame(height: 18)

            comparisonPicker

            Divider().frame(height: 18)

            Menu {
                ForEach(DiffGranularity.allCases) { g in
                    Button(g.menuTitle) {
                        documentManager.setDiffGranularity(g)
                    }
                }
            } label: {
                Text(diff.granularity.menuTitle)
            }
            .help("Word or block diff granularity")

            Spacer()

            Button(action: { documentManager.exitDiffMode() }) {
                Label("Close Diff", systemImage: "xmark.circle")
            }
            .help("Close Diff Mode (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(themeService.currentTheme.colors.code.opacity(0.5))
    }

    private var changeCounterText: String {
        if diff.totalChanges == 0 {
            return "No changes"
        }
        return "Change \(diff.currentChangeIndex) of \(diff.totalChanges)"
    }

    private var comparisonPicker: some View {
        Menu {
            Button {
                documentManager.selectDiffSnapshot(id: nil)
            } label: {
                Label("Previous version (auto)", systemImage: isAutoComparison ? "checkmark" : "")
            }

            if !historySnapshots.isEmpty {
                Section("Version history") {
                    ForEach(historySnapshots) { snapshot in
                        Button {
                            documentManager.selectDiffSnapshot(id: snapshot.id)
                        } label: {
                            Label(
                                snapshotMenuTitle(snapshot),
                                systemImage: isSelectedSnapshot(snapshot.id) ? "checkmark" : ""
                            )
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        documentManager.clearVersionHistory()
                    } label: {
                        Label("Clear Version History", systemImage: "trash")
                    }
                }
            }

            Section("External file") {
                Button("Compare with file…") {
                    documentManager.pickExternalComparisonFile()
                }
                if diff.externalBaseline != nil {
                    Button("Clear external comparison") {
                        documentManager.clearExternalComparison()
                    }
                }
            }
        } label: {
            Text("Comparing: \(comparingLabel)")
        }
    }

    /// Snapshots shown in history (skip ephemeral Unsaved at top when it only mirrors editor).
    private var historySnapshots: [DocumentSnapshot] {
        diff.snapshots.filter { $0.label != "Unsaved" }
    }

    private var comparingLabel: String {
        switch diff.comparisonSource {
        case .externalFile:
            return diff.externalBaseline?.fileName ?? "External file"
        case .snapshot(let id):
            if let snap = diff.snapshots.first(where: { $0.id == id }) {
                return snap.menuLabel
            }
            return "Snapshot"
        case .previousVersion:
            return "Previous version"
        }
    }

    private func snapshotMenuTitle(_ snapshot: DocumentSnapshot) -> String {
        var title = snapshot.menuLabel
        if let current = documentManager.currentDocument?.content,
           snapshot.content == current {
            title += " (matches editor)"
        }
        return title
    }

    private var isAutoComparison: Bool {
        if case .previousVersion = diff.comparisonSource { return true }
        return false
    }

    private func isSelectedSnapshot(_ id: UUID) -> Bool {
        if case .snapshot(let selectedID) = diff.comparisonSource {
            return selectedID == id
        }
        return diff.selectedSnapshotID == id
    }
}

private extension DocumentSnapshot {
    var menuLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        let datePart = f.string(from: createdAt)
        if let label, !label.isEmpty {
            return "\(datePart) — \(label)"
        }
        return datePart
    }
}
