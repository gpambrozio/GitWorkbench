import SwiftUI

/// One side (left = old, right = new) of a split diff row.
struct SplitSide: View {
    enum Side { case left, right }
    @Environment(\.workbenchTheme) private var theme
    let cell: DiffLine?
    let side: Side

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
            Text(cellText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 10)
                .foregroundStyle(cell == nil ? .clear : theme.ink)
        }
        .frame(minHeight: Tokens.diffLineHeight)
        .background(background)
        .overlay(alignment: .trailing) {
            if side == .left { Rectangle().fill(theme.sep).frame(width: 1) }
        }
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

/// One split row: left side + right side.
struct SplitDiffRow: View {
    let row: SplitRow
    var body: some View {
        HStack(spacing: 0) {
            SplitSide(cell: row.left, side: .left)
            SplitSide(cell: row.right, side: .right)
        }
        .font(.system(size: 12, design: .monospaced))
    }
}
