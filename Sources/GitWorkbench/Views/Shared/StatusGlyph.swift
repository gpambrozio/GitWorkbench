import SwiftUI

/// Rounded-square status badge: outlined when unselected, filled (with a white letter) when selected.
struct StatusGlyph: View {
    @Environment(\.workbenchTheme) private var theme
    let status: FileStatus
    var selected: Bool = false
    var size: CGFloat = Tokens.statusGlyphSize

    var body: some View {
        let color = theme.color(for: status)
        RoundedRectangle(cornerRadius: Tokens.glyphRadius, style: .continuous)
            .fill(selected ? color : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.glyphRadius, style: .continuous)
                    .strokeBorder(selected ? .clear : color, lineWidth: Tokens.glyphStroke)
            )
            .overlay(
                Text(status.rawValue)
                    .font(.system(size: size * 0.6, weight: .bold))
                    .foregroundStyle(selected ? Color.white : color)
            )
            .frame(width: size, height: size)
    }
}

#Preview("StatusGlyph") {
    HStack(spacing: 8) {
        ForEach(FileStatus.allCases, id: \.self) { StatusGlyph(status: $0) }
        Divider().frame(height: 20)
        ForEach(FileStatus.allCases, id: \.self) { StatusGlyph(status: $0, selected: true) }
    }
    .padding()
    .background(Color(hex: 0x7C5CE0).opacity(0.5))
}
