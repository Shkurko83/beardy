import SwiftUI
import AppKit

struct DocumentTabBar: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var themeService: ThemeService

    @State private var draggedTabID: UUID?
    @State private var hoveredDropIndex: Int?

    private let barHeight: CGFloat = 48

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 0) {
                    ForEach(Array(documentManager.tabs.enumerated()), id: \.element.id) { index, tab in
                        TabDropSlot(
                            isActive: hoveredDropIndex == index,
                            onTargetChange: { isTargeted in
                                if isTargeted {
                                    hoveredDropIndex = index
                                } else if hoveredDropIndex == index {
                                    hoveredDropIndex = nil
                                }
                            },
                            onDrop: { payload in
                                handleDrop(payload: payload, toIndex: index)
                            }
                        )

                        DocumentTabItem(
                            tab: tab,
                            isSelected: documentManager.selectedTabID == tab.id,
                            isDragging: draggedTabID == tab.id
                        ) {
                            documentManager.selectTab(tab.id)
                        } onClose: {
                            documentManager.closeTab(tab.id)
                        }
                        .id(tab.id)
                        .onDrag {
                            draggedTabID = tab.id
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                    }

                    TabDropSlot(
                        isActive: hoveredDropIndex == documentManager.tabs.count,
                        onTargetChange: { isTargeted in
                            if isTargeted {
                                hoveredDropIndex = documentManager.tabs.count
                            } else if hoveredDropIndex == documentManager.tabs.count {
                                hoveredDropIndex = nil
                            }
                        },
                        onDrop: { payload in
                            handleDrop(payload: payload, toIndex: documentManager.tabs.count)
                        }
                    )

                    Button(action: { documentManager.createNewDocument() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("New tab")
                    .padding(.leading, 6)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: barHeight)
                .animation(nil, value: documentManager.tabs.map(\.id))
            }
            .frame(height: barHeight)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: documentManager.selectedTabID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
        .frame(height: barHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(themeService.currentTheme.colors.background)
    }

    private func handleDrop(payload: [String], toIndex: Int) -> Bool {
        defer {
            draggedTabID = nil
            hoveredDropIndex = nil
        }
        guard let dragged = payload.first,
              let draggedID = UUID(uuidString: dragged) else { return false }
        documentManager.moveTab(from: draggedID, toIndex: toIndex)
        return true
    }
}

// MARK: - Drop slot with blue insertion marker

private struct TabDropSlot: View {
    let isActive: Bool
    let onTargetChange: (Bool) -> Void
    let onDrop: ([String]) -> Bool

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 12)
                .contentShape(Rectangle())

            if isActive {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 26)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 2)
            }
        }
        .frame(width: 12, height: 32)
        .dropDestination(for: String.self) { items, _ in
            onDrop(items)
        } isTargeted: { targeted in
            onTargetChange(targeted)
        }
    }
}

// MARK: - Tab item

private struct DocumentTabItem: View {
    @EnvironmentObject private var themeService: ThemeService

    let tab: EditorTab
    let isSelected: Bool
    var isDragging: Bool = false
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        themeService.currentTheme.colors
    }

    private var showsCloseButton: Bool {
        isHovered || isSelected
    }

    private var tabBackground: Color {
        if isSelected {
            return colors.selection.opacity(themeService.currentTheme.isDark ? 0.45 : 0.35)
        }
        if isHovered {
            return colors.selection.opacity(themeService.currentTheme.isDark ? 0.22 : 0.16)
        }
        return colors.code
    }

    private var tabBorder: Color {
        if isSelected {
            return colors.link.opacity(0.65)
        }
        if isHovered {
            return colors.secondaryText.opacity(0.35)
        }
        return colors.border
    }

    private var tabBorderWidth: CGFloat {
        isSelected ? 1.5 : 1
    }

    private var iconColor: Color {
        isSelected ? colors.link : colors.secondaryText
    }

    private var titleColor: Color {
        isSelected ? colors.text : colors.secondaryText
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundColor(iconColor)
                        .frame(width: 14)

                    Text(tab.document.fileName)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 130, alignment: .leading)
                        .foregroundColor(titleColor)

                    if tab.document.hasUnsavedChanges {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    } else {
                        Color.clear.frame(width: 6, height: 6)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .padding(.trailing, 28)
                .padding(.vertical, 6)
                .frame(height: 32)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(colors.secondaryText)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Close tab")
            .opacity(showsCloseButton ? 1 : 0)
            .allowsHitTesting(showsCloseButton)
            .padding(.trailing, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tabBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tabBorder, lineWidth: tabBorderWidth)
        )
        .opacity(isDragging ? 0.45 : 1)
        .onHover { isHovered = $0 }
    }
}
