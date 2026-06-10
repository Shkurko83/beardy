import SwiftUI

struct DiffMinimap: View {
    let segments: [DiffMinimapSegment]
    let currentChangeIndex: Int
    let onSelect: (Int) -> Void

    @EnvironmentObject private var themeService: ThemeService

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(themeService.currentTheme.colors.border.opacity(0.35))

                ForEach(segments) { segment in
                    let height = max(4, geo.size.height * segment.length)
                    let y = geo.size.height * segment.start
                    RoundedRectangle(cornerRadius: 1)
                        .fill(segment.isInsertion ? Color.green.opacity(0.85) : Color.red.opacity(0.85))
                        .frame(width: geo.size.width, height: height)
                        .offset(y: y)
                        .overlay {
                            if segment.id == currentChangeIndex {
                                RoundedRectangle(cornerRadius: 1)
                                    .stroke(themeService.currentTheme.colors.heading, lineWidth: 1)
                                    .frame(width: geo.size.width, height: height)
                                    .offset(y: y)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(segment.id)
                        }
                }
            }
        }
        .frame(width: 8)
        .padding(.vertical, 8)
        .padding(.trailing, 6)
        .accessibilityLabel("Change minimap")
    }
}
