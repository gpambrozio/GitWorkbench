import SwiftUI

/// The `@@ … @@` hunk header band.
struct HunkHeaderBand: View {
    @Environment(\.workbenchTheme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(theme.ink3)
            .lineLimit(1)
            .padding(.vertical, 5)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.hunkHeaderBg)
            .overlay(alignment: .top) { Rectangle().fill(theme.sep).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }
}

/// One unified diff line: [oldNo][newNo][sign][code], tinted by kind.
struct UnifiedDiffRow: View {
    @Environment(\.workbenchTheme) private var theme
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            gutter(line.oldNumber)
            gutter(line.newNumber)
            Text(sign)
                .frame(width: Tokens.unifiedSignWidth)
                .foregroundStyle(signColor)
                .fontWeight(.bold)
            Text(line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 16)
                .foregroundStyle(theme.ink)
        }
        .font(.system(size: 12, design: .monospaced))
        .lineLimit(1)
        .frame(minHeight: Tokens.diffLineHeight)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(edgeBar).frame(width: Tokens.diffEdgeBarWidth)
        }
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .foregroundStyle(theme.ink3)
            .padding(.trailing, 12)
            .frame(width: Tokens.unifiedGutterWidth, alignment: .trailing)
    }

    private var sign: String {
        switch line.kind { case .addition: "+"; case .deletion: "\u{2212}"; case .context: " " }
    }
    private var signColor: Color {
        switch line.kind { case .addition: theme.addInk; case .deletion: theme.delInk; case .context: theme.ink3 }
    }
    private var rowBackground: Color {
        switch line.kind { case .addition: theme.addBg; case .deletion: theme.delBg; case .context: .clear }
    }
    private var edgeBar: Color {
        switch line.kind { case .addition: theme.addGut; case .deletion: theme.delGut; case .context: .clear }
    }
}
