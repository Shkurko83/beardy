import SwiftUI
import AppKit

// MARK: - Panel layout animation

enum PanelLayoutAnimation {
    static let slide = Animation.easeInOut(duration: AppConstants.Animations.defaultDuration)

    static var leadingPanel: AnyTransition {
        .move(edge: .leading).combined(with: .opacity)
    }

    static var trailingPanel: AnyTransition {
        .move(edge: .trailing).combined(with: .opacity)
    }
}

// MARK: - Width constraints & window-aware layout

struct PanelLayoutMetrics: Equatable {
    let sidebarWidth: CGFloat
    let outlineWidth: CGFloat
}

enum PanelWidthConstraints {
    /// Minimum width while the user drags a resize handle.
    static let minWidth: CGFloat = 200
    /// Minimum width when the window is too narrow (window squeeze only).
    static let minWidthWhenCompressed: CGFloat = 120
    static let minEditorWidth: CGFloat = 280
    static let maxWidthFraction: CGFloat = 0.30
    static let handleWidth: CGFloat = 6

    static func maxWidth(for containerWidth: CGFloat) -> CGFloat {
        max(minWidthWhenCompressed, containerWidth * maxWidthFraction)
    }

    /// Restores corrupt/zero stored widths to defaults while keeping valid user preferences.
    static func sanitizedStoredWidth(_ width: CGFloat, defaultWidth: CGFloat) -> CGFloat {
        guard width >= minWidthWhenCompressed else { return defaultWidth }
        return width
    }

    /// Resolves sidebar and outline widths so panels + editor fit in the window.
    static func resolve(
        windowWidth: CGFloat,
        sidebarVisible: Bool,
        outlineVisible: Bool,
        sidebarPreferred: CGFloat,
        outlinePreferred: CGFloat
    ) -> PanelLayoutMetrics {
        guard windowWidth > 0 else {
            return PanelLayoutMetrics(sidebarWidth: 0, outlineWidth: 0)
        }

        let sidebarPref = sanitizedStoredWidth(sidebarPreferred, defaultWidth: AppConstants.Defaults.sidebarWidth)
        let outlinePref = sanitizedStoredWidth(outlinePreferred, defaultWidth: AppConstants.Defaults.outlineWidth)

        var sidebar = sidebarVisible ? sidebarPref : 0
        var outline = outlineVisible ? outlinePref : 0

        if sidebarVisible {
            sidebar = min(sidebar, maxWidth(for: windowWidth))
        }
        if outlineVisible {
            outline = min(outline, maxWidth(for: windowWidth))
        }

        shrinkToFit(windowWidth: windowWidth, sidebarVisible: sidebarVisible, outlineVisible: outlineVisible, sidebar: &sidebar, outline: &outline)

        if sidebarVisible {
            sidebar = applyUserMinimum(
                current: sidebar,
                preferred: sidebarPref,
                windowWidth: windowWidth,
                sidebarVisible: sidebarVisible,
                outlineVisible: outlineVisible,
                sidebar: sidebar,
                outline: outline,
                panel: .sidebar
            )
        }
        if outlineVisible {
            outline = applyUserMinimum(
                current: outline,
                preferred: outlinePref,
                windowWidth: windowWidth,
                sidebarVisible: sidebarVisible,
                outlineVisible: outlineVisible,
                sidebar: sidebar,
                outline: outline,
                panel: .outline
            )
        }

        shrinkToFit(windowWidth: windowWidth, sidebarVisible: sidebarVisible, outlineVisible: outlineVisible, sidebar: &sidebar, outline: &outline)

        return PanelLayoutMetrics(sidebarWidth: max(0, sidebar), outlineWidth: max(0, outline))
    }

    static func clamp(
        _ width: CGFloat,
        windowWidth: CGFloat,
        sidebarVisible: Bool,
        outlineVisible: Bool,
        sidebarPreferred: CGFloat,
        outlinePreferred: CGFloat,
        panel: PanelSide
    ) -> CGFloat {
        let preferred: CGFloat
        switch panel {
        case .sidebar:
            preferred = width
        case .outline:
            preferred = width
        }
        let metrics = resolve(
            windowWidth: windowWidth,
            sidebarVisible: sidebarVisible,
            outlineVisible: outlineVisible,
            sidebarPreferred: panel == .sidebar ? preferred : sidebarPreferred,
            outlinePreferred: panel == .outline ? preferred : outlinePreferred
        )
        return panel == .sidebar ? metrics.sidebarWidth : metrics.outlineWidth
    }

    /// Updates stored widths after window resize. Hidden panels keep their saved preference (never written as 0).
    static func clampStored(
        sidebar: inout Double,
        outline: inout Double,
        windowWidth: CGFloat,
        sidebarVisible: Bool,
        outlineVisible: Bool
    ) {
        let sidebarPref = sanitizedStoredWidth(CGFloat(sidebar), defaultWidth: AppConstants.Defaults.sidebarWidth)
        let outlinePref = sanitizedStoredWidth(CGFloat(outline), defaultWidth: AppConstants.Defaults.outlineWidth)

        if sidebarVisible {
            sidebar = Double(
                resolve(
                    windowWidth: windowWidth,
                    sidebarVisible: true,
                    outlineVisible: outlineVisible,
                    sidebarPreferred: sidebarPref,
                    outlinePreferred: outlinePref
                ).sidebarWidth
            )
        } else {
            sidebar = Double(sidebarPref)
        }

        if outlineVisible {
            outline = Double(
                resolve(
                    windowWidth: windowWidth,
                    sidebarVisible: sidebarVisible,
                    outlineVisible: true,
                    sidebarPreferred: sidebarPref,
                    outlinePreferred: outlinePref
                ).outlineWidth
            )
        } else {
            outline = Double(outlinePref)
        }
    }

    // Legacy single-panel helpers
    static func clamp(_ width: CGFloat, containerWidth: CGFloat) -> CGFloat {
        resolve(
            windowWidth: containerWidth,
            sidebarVisible: true,
            outlineVisible: false,
            sidebarPreferred: width,
            outlinePreferred: 0
        ).sidebarWidth
    }

    static func clampStored(_ stored: inout Double, containerWidth: CGFloat) {
        var outline: Double = 0
        clampStored(sidebar: &stored, outline: &outline, windowWidth: containerWidth, sidebarVisible: true, outlineVisible: false)
    }

    enum PanelSide {
        case sidebar
        case outline
    }

    private static func chromeWidth(
        windowWidth: CGFloat,
        sidebarVisible: Bool,
        outlineVisible: Bool,
        sidebar: CGFloat,
        outline: CGFloat
    ) -> CGFloat {
        var used = minEditorWidth
        if sidebarVisible { used += sidebar + handleWidth }
        if outlineVisible { used += outline + handleWidth }
        return used
    }

    private static func shrinkToFit(
        windowWidth: CGFloat,
        sidebarVisible: Bool,
        outlineVisible: Bool,
        sidebar: inout CGFloat,
        outline: inout CGFloat
    ) {
        while chromeWidth(windowWidth: windowWidth, sidebarVisible: sidebarVisible, outlineVisible: outlineVisible, sidebar: sidebar, outline: outline) > windowWidth {
            let canShrinkSidebar = sidebarVisible && sidebar > minWidthWhenCompressed
            let canShrinkOutline = outlineVisible && outline > minWidthWhenCompressed
            if !canShrinkSidebar && !canShrinkOutline { break }

            if canShrinkSidebar && (!canShrinkOutline || sidebar >= outline) {
                sidebar -= 1
            } else if canShrinkOutline {
                outline -= 1
            } else {
                break
            }
        }
    }

    private static func applyUserMinimum(
        current: CGFloat,
        preferred: CGFloat,
        windowWidth: CGFloat,
        sidebarVisible: Bool,
        outlineVisible: Bool,
        sidebar: CGFloat,
        outline: CGFloat,
        panel: PanelSide
    ) -> CGFloat {
        let target = min(preferred, maxWidth(for: windowWidth))
        guard target >= minWidth else { return current }

        var testSidebar = sidebar
        var testOutline = outline
        switch panel {
        case .sidebar: testSidebar = target
        case .outline: testOutline = target
        }

        if chromeWidth(windowWidth: windowWidth, sidebarVisible: sidebarVisible, outlineVisible: outlineVisible, sidebar: testSidebar, outline: testOutline) <= windowWidth {
            return max(current, minWidth)
        }
        return current
    }
}

// MARK: - Resize handle

struct PanelResizeHandle: View {
    enum PanelEdge {
        case leadingPanel
        case trailingPanel
    }

    let width: CGFloat
    let windowWidth: CGFloat
    let sidebarVisible: Bool
    let outlineVisible: Bool
    let sidebarPreferred: CGFloat
    let outlinePreferred: CGFloat
    let edge: PanelEdge
    let onWidthChange: (CGFloat) -> Void
    let onDragEnded: () -> Void

    @EnvironmentObject private var themeService: ThemeService
    @GestureState private var isDragging = false
    @State private var widthAtDragStart: CGFloat?
    @State private var isHovering = false

    private var panelSide: PanelWidthConstraints.PanelSide {
        edge == .leadingPanel ? .sidebar : .outline
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(themeService.currentTheme.colors.border.opacity(isHovering || isDragging ? 0.9 : 0.35))
                .frame(width: 1)

            Rectangle()
                .fill(Color.accentColor.opacity(isHovering || isDragging ? 0.2 : 0))
        }
        .frame(width: PanelWidthConstraints.handleWidth)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard widthAtDragStart == nil else { return }
            switch phase {
            case .active:
                isHovering = true
                NSCursor.resizeLeftRight.push()
            case .ended:
                isHovering = false
                NSCursor.pop()
            }
        }
        .gesture(dragGesture)
        .accessibilityLabel("Resize panel")
        .accessibilityAddTraits(.isButton)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                if widthAtDragStart == nil {
                    widthAtDragStart = width
                }
                let delta = edge == .leadingPanel ? value.translation.width : -value.translation.width
                let raw = (widthAtDragStart ?? width) + delta
                let clamped = PanelWidthConstraints.clamp(
                    raw,
                    windowWidth: windowWidth,
                    sidebarVisible: sidebarVisible,
                    outlineVisible: outlineVisible,
                    sidebarPreferred: sidebarPreferred,
                    outlinePreferred: outlinePreferred,
                    panel: panelSide
                )
                onWidthChange(clamped)
            }
            .onEnded { _ in
                widthAtDragStart = nil
                onDragEnded()
            }
    }
}
