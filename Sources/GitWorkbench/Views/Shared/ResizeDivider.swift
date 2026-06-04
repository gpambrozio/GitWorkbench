import SwiftUI

/// Live, resizable widths for the workbench's columns, seeded from `configuration.layout`. Owned by
/// `GitWorkbenchView` and shared with the workspace bodies through the environment, so a drag persists
/// while switching Changes/History/Stash.
///
/// Persistence is delegated to the host via `configuration.layoutStore` (keyed by `persistenceKey`):
/// widths are loaded on init and saved on every change. With no store the layout is purely in-session —
/// the component never touches `UserDefaults` itself.
final class ColumnLayout: ObservableObject {
    @Published var railWidth: CGFloat { didSet { persist() } }
    @Published var changesListWidth: CGFloat { didSet { persist() } }
    @Published var historyListWidth: CGFloat { didSet { persist() } }

    let railRange: ClosedRange<CGFloat>
    let changesListRange: ClosedRange<CGFloat>
    let historyListRange: ClosedRange<CGFloat>

    private let store: WorkbenchLayoutStore?
    private let key: String

    private enum Column {
        static let rail = "rail"
        static let changesList = "changesList"
        static let historyList = "historyList"
    }

    init(configuration: WorkbenchConfiguration = .init()) {
        let l = configuration.layout
        let store = configuration.layoutStore
        let key = configuration.persistenceKey ?? ""
        self.store = store
        self.key = key

        let railRange = l.minRailWidth...max(l.minRailWidth + 60, 340)
        let changesRange: ClosedRange<CGFloat> = 240...560
        let historyRange: ClosedRange<CGFloat> = 260...600
        self.railRange = railRange
        self.changesListRange = changesRange
        self.historyListRange = historyRange

        // Initial assignments don't trip `didSet`, so restoring here never writes back.
        let saved = store?.load(key)
        self.railWidth = Self.value(saved, Column.rail, fallback: l.railWidth, range: railRange)
        self.changesListWidth = Self.value(saved, Column.changesList, fallback: l.changesListWidth, range: changesRange)
        self.historyListWidth = Self.value(saved, Column.historyList, fallback: l.historyListWidth, range: historyRange)
    }

    private static func value(_ saved: [String: CGFloat]?, _ name: String,
                              fallback: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        guard let v = saved?[name] else { return fallback }
        return min(range.upperBound, max(range.lowerBound, v))   // clamp in case ranges changed
    }

    private func persist() {
        store?.save(key, [Column.rail: railWidth,
                          Column.changesList: changesListWidth,
                          Column.historyList: historyListWidth])
    }
}

/// A 1px column separator with a wider invisible grab strip: drag to resize the column to its left,
/// clamped to `range`. Shows the column-resize cursor on hover and tints the line while active.
struct ResizeDivider: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    @Environment(\.workbenchTheme) private var theme
    @State private var dragStart: CGFloat?
    @State private var hovering = false

    var body: some View {
        let active = hovering || dragStart != nil
        Rectangle()
            .fill(active ? theme.accent : theme.sep)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 11)
                    .contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .onHover { hovering = $0 }
                    .gesture(
                        // Measure in GLOBAL space: the divider moves as the column resizes, so a
                        // `.local` translation would shift under the cursor each frame (jitter + drift).
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let base = dragStart ?? width
                                if dragStart == nil { dragStart = base }
                                width = min(range.upperBound, max(range.lowerBound, base + value.translation.width))
                            }
                            .onEnded { _ in dragStart = nil }
                    )
            }
    }
}
