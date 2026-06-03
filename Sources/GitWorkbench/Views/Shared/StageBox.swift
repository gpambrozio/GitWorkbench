import SwiftUI

/// 15×15 staging checkbox: empty / accent-check (checked) / accent-dash (partial).
struct StageBox: View {
    @Environment(\.workbenchTheme) private var theme
    var checked: Bool
    var partial: Bool = false

    var body: some View {
        let filled = checked || partial
        RoundedRectangle(cornerRadius: Tokens.glyphRadius, style: .continuous)
            .fill(filled ? theme.accent : theme.field)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.glyphRadius, style: .continuous)
                    .strokeBorder(filled ? .clear : theme.sepStrong, lineWidth: Tokens.glyphStroke)
            )
            .overlay {
                if partial {
                    Image(systemName: IconLibrary.minus).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                } else if checked {
                    Image(systemName: IconLibrary.check).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: Tokens.stageBoxSize, height: Tokens.stageBoxSize)
    }
}

#Preview("StageBox") {
    HStack(spacing: 10) {
        StageBox(checked: false)
        StageBox(checked: true)
        StageBox(checked: false, partial: true)
    }
    .padding()
}
