import SwiftUI

/// Branch glyph + name (+ optional chevron). `dim` is the read-only variant.
struct BranchPill: View {
    @Environment(\.workbenchTheme) private var theme
    let name: String
    var dim: Bool = false
    var showsChevron: Bool = true
    var height: CGFloat = 28
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { content }.buttonStyle(PressableButtonStyle())
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 6) {
            Image(systemName: IconLibrary.branch)
                .foregroundStyle(dim ? theme.ink3 : theme.accent)
            Text(name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.ink)
            if showsChevron {
                Image(systemName: IconLibrary.chevronUpDown)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.ink3)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(Color.black.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
    }
}

#Preview("BranchPill") {
    VStack(spacing: 8) {
        BranchPill(name: "feat/auto-sync") {}
        BranchPill(name: "main", dim: true, showsChevron: false, height: 24)
    }
    .padding()
}
