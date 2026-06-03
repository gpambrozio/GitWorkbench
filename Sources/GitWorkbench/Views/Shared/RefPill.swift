import SwiftUI

/// A HEAD / branch / tag pill shown on a commit row.
struct RefPill: View {
    @Environment(\.workbenchTheme) private var theme
    let ref: CommitRef
    var selected: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let icon = IconLibrary.symbol(for: ref) { Image(systemName: icon).font(.system(size: 8)) }
            Text(label)
        }
        .font(.system(size: 9.5, weight: .bold))
        .padding(.horizontal, 5).padding(.vertical, 1)
        .foregroundStyle(selected ? .white : foreground)
        .background(selected ? Color.white.opacity(0.22) : background,
                    in: RoundedRectangle(cornerRadius: Tokens.pillRadius, style: .continuous))
    }

    private var label: String {
        switch ref { case .head: "HEAD"; case .branch(let n): n; case .tag(let t): t }
    }
    private var foreground: Color {
        switch ref { case .head: theme.accentDeep; case .branch: theme.statusRenamed; case .tag: theme.statusAdded }
    }
    private var background: Color {
        switch ref {
        case .head: theme.accentSoft
        case .branch: theme.statusRenamed.opacity(0.13)
        case .tag: theme.statusAdded.opacity(0.13)
        }
    }
}
