import SwiftUI
import AppKit

/// Measurement + layout constants shared by the unified and split diff renderers.
enum DiffMetrics {
    /// Computed (not a stored global) so it stays clear of Swift 6's non-`Sendable` global rule.
    static var monoFont: NSFont { .monospacedSystemFont(ofSize: 12, weight: .regular) }
    /// Right inset between a side's code column and the pane edge / divider.
    static let splitCodeInset: CGFloat = 10
    /// Height of the reserved horizontal scroll-bar strip under the split panes.
    static let splitScrollBarHeight: CGFloat = 14

    /// Width of the widest code line in the diff, measured once in the diff mono font.
    static func maxCodeWidth(_ diff: FileDiff) -> CGFloat {
        guard let longest = diff.hunks.flatMap(\.lines).map(\.text).max(by: { $0.count < $1.count }) else { return 0 }
        return (longest as NSString).size(withAttributes: [.font: monoFont]).width
    }

    /// Visible width of one side's code column, given the pane (half-window) width.
    static func splitCodeWidth(paneWidth: CGFloat) -> CGFloat {
        max(0, paneWidth - Tokens.splitGutterWidth - Tokens.splitSignWidth - splitCodeInset)
    }
}

/// The split diff: two half-width panes with the divider pinned at the centre. Gutters, signs and the
/// `@@` header bands stay fixed; only the code columns scroll horizontally, in lock-step across both
/// sides (VSCode-style). Vertical scrolling is shared by the single outer `ScrollView`; horizontal
/// input is captured by `HorizontalScrollCatcher` and drives `hOffset`.
struct SplitDiffBody: View {
    @Environment(\.workbenchTheme) private var theme
    let diff: FileDiff
    @State private var hOffset: CGFloat = 0

    var body: some View {
        let maxCode = DiffMetrics.maxCodeWidth(diff)
        return GeometryReader { geo in
            let paneWidth = geo.size.width / 2
            let codeWidth = DiffMetrics.splitCodeWidth(paneWidth: paneWidth)
            let maxOffset = max(0, maxCode + DiffMetrics.splitCodeInset - codeWidth)
            let offset = min(hOffset, maxOffset)
            let showBar = maxOffset > 0
            let viewportHeight = geo.size.height - (showBar ? DiffMetrics.splitScrollBarHeight : 0)
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diff.hunks) { hunk in
                            HunkHeaderBand(text: hunk.header)
                            ForEach(DiffSplitter.rows(hunk.lines)) { row in
                                SplitDiffRow(row: row, paneWidth: paneWidth, codeWidth: codeWidth, codeOffset: offset)
                            }
                        }
                    }
                    .frame(width: geo.size.width, alignment: .topLeading)
                    .frame(minHeight: viewportHeight, alignment: .topLeading)   // top-align short diffs
                    .overlay {
                        HorizontalScrollCatcher(offset: offset, maxOffset: maxOffset) { hOffset = $0 }
                    }
                }
                if showBar {
                    scrollBars(paneWidth: paneWidth, codeWidth: codeWidth, maxOffset: maxOffset)
                        .frame(height: DiffMetrics.splitScrollBarHeight)
                        .background(theme.winBg)
                        .overlay(alignment: .top) { Rectangle().fill(theme.sep).frame(height: 1) }
                }
            }
        }
    }

    /// One scroll bar per side, each sitting under its pane's code column (so it lines up with the text
    /// that actually moves). Both drive the shared `hOffset`, so dragging either scrolls both sides.
    private func scrollBars(paneWidth: CGFloat, codeWidth: CGFloat, maxOffset: CGFloat) -> some View {
        HStack(spacing: 0) {
            barCell(paneWidth: paneWidth, codeWidth: codeWidth, maxOffset: maxOffset)
            barCell(paneWidth: paneWidth, codeWidth: codeWidth, maxOffset: maxOffset)
        }
    }

    private func barCell(paneWidth: CGFloat, codeWidth: CGFloat, maxOffset: CGFloat) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0).frame(width: Tokens.splitGutterWidth + Tokens.splitSignWidth)
            DiffScrollBar(offset: $hOffset, maxOffset: maxOffset, trackWidth: codeWidth)
            Spacer(minLength: 0).frame(width: DiffMetrics.splitCodeInset)
        }
        .frame(width: paneWidth)
    }
}

/// A thin, always-visible horizontal scroll bar for one split pane's code column. It is laid out in its
/// own reserved strip (not over the content), so a mouse with no horizontal wheel can drag the thumb.
struct DiffScrollBar: View {
    @Environment(\.workbenchTheme) private var theme
    @Binding var offset: CGFloat
    let maxOffset: CGFloat       // always > 0 where this is shown
    let trackWidth: CGFloat
    @State private var hovering = false
    @State private var dragStart: CGFloat?

    private var contentWidth: CGFloat { trackWidth + maxOffset }
    private var thumbWidth: CGFloat { max(28, trackWidth * trackWidth / max(contentWidth, 1)) }
    private var thumbTravel: CGFloat { max(1, trackWidth - thumbWidth) }

    var body: some View {
        let progress = min(1, max(0, offset / maxOffset))
        Capsule()
            .fill(theme.ink3.opacity(hovering || dragStart != nil ? 0.55 : 0.30))
            .frame(width: thumbWidth, height: 6)
            .offset(x: progress * thumbTravel)
            .frame(width: trackWidth, height: DiffMetrics.splitScrollBarHeight, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let base = dragStart ?? offset
                        if dragStart == nil { dragStart = base }
                        let delta = value.translation.width * (maxOffset / thumbTravel)
                        offset = min(maxOffset, max(0, base + delta))
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }
}

/// One split row: left side + right side, each a fixed half-pane.
struct SplitDiffRow: View {
    let row: SplitRow
    let paneWidth: CGFloat
    let codeWidth: CGFloat
    let codeOffset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            SplitSide(cell: row.left, side: .left, paneWidth: paneWidth, codeWidth: codeWidth, codeOffset: codeOffset)
            SplitSide(cell: row.right, side: .right, paneWidth: paneWidth, codeWidth: codeWidth, codeOffset: codeOffset)
        }
        .font(.system(size: 12, design: .monospaced))
    }
}

/// One side (left = old, right = new) of a split diff row. The line number + sign are pinned; the code
/// text is shifted by `codeOffset` and clipped to `codeWidth`, so long lines slide under a fixed gutter.
struct SplitSide: View {
    enum Side { case left, right }
    @Environment(\.workbenchTheme) private var theme
    let cell: DiffLine?
    let side: Side
    let paneWidth: CGFloat
    let codeWidth: CGFloat
    let codeOffset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text(number)
                .foregroundStyle(theme.ink3)
                .padding(.trailing, 10)
                .frame(width: Tokens.splitGutterWidth, alignment: .trailing)
            Text(sign)
                .frame(width: Tokens.splitSignWidth)
                .foregroundStyle(signColor)
                .fontWeight(.bold)
            code
        }
        .frame(width: paneWidth, alignment: .leading)
        .frame(minHeight: Tokens.diffLineHeight)
        .background(background)
        .overlay(alignment: .trailing) {
            if side == .left { Rectangle().fill(theme.sep).frame(width: 1) }
        }
    }

    /// Full-width code, shifted left by the shared offset and clipped to the column. No truncation —
    /// long lines scroll into view instead of ellipsizing. `.leading` keeps the overflow on the right.
    private var code: some View {
        Text(cellText)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(cell == nil ? .clear : theme.ink)
            .offset(x: -codeOffset)
            .frame(width: codeWidth, height: Tokens.diffLineHeight, alignment: .leading)
            .clipped()
            .padding(.trailing, DiffMetrics.splitCodeInset)
    }

    private var number: String {
        guard let cell else { return "" }
        let n = side == .left ? cell.oldNumber : cell.newNumber
        return n.map(String.init) ?? ""
    }
    private var isChange: Bool { cell != nil && cell!.kind != .context }
    private var sign: String { isChange ? (cell!.kind == .addition ? "+" : "\u{2212}") : "" }
    private var signColor: Color { cell?.kind == .addition ? theme.addInk : theme.delInk }
    private var cellText: String {
        guard let cell else { return "" }
        return cell.text.isEmpty ? " " : cell.text
    }
    private var background: Color {
        guard let cell else { return theme.splitEmptyCell }
        switch cell.kind { case .addition: return theme.addBg; case .deletion: return theme.delBg; case .context: return .clear }
    }
}
