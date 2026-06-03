import SwiftUI

/// "+N −N" addition/deletion counts in tabular mono. Hides a side when its count is zero.
struct StatChips: View {
    @Environment(\.workbenchTheme) private var theme
    var additions: Int
    var deletions: Int
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 6) {
            if additions > 0 {
                Text("+\(additions)").foregroundStyle(theme.addInk)
            }
            if deletions > 0 {
                Text("\u{2212}\(deletions)").foregroundStyle(theme.delInk)   // U+2212 MINUS SIGN
            }
        }
        .font(.system(size: size, weight: .semibold).monospacedDigit())
    }
}

#Preview("StatChips") {
    VStack(alignment: .leading) {
        StatChips(additions: 24, deletions: 6)
        StatChips(additions: 31, deletions: 0)
        StatChips(additions: 0, deletions: 18)
    }
    .padding()
}
