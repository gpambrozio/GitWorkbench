import SwiftUI

/// Toolbar / diff-header button. Roles: normal (idle/active), primary (accent), danger.
struct ToolButton: View {
    enum Role { case normal, primary, danger }

    @Environment(\.workbenchTheme) private var theme
    var icon: String? = nil
    var label: String? = nil
    /// Optional trailing count rendered as a neutral capsule badge (e.g. commits to pull/push).
    /// Hidden when nil or non-positive. Matches the Staged/Changes header badge.
    var badge: Int? = nil
    var active: Bool = false
    var role: Role = .normal
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                if let label { Text(label) }
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(theme.ink3)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.black.opacity(0.06), in: Capsule())
                }
            }
            .font(.system(size: 12.5, weight: role == .primary ? .semibold : .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 28)
            // Size to the content's intrinsic width so a wide badge (e.g. 3-digit count)
            // grows the button instead of truncating the label/badge to "P…".
            .fixedSize(horizontal: true, vertical: false)
            .background(background, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var foreground: Color {
        switch role {
        case .normal:  return theme.ink2
        case .primary: return .white
        case .danger:  return theme.delInk
        }
    }

    private var background: Color {
        switch role {
        case .normal:  return active ? Color.black.opacity(0.08) : .clear
        case .primary: return theme.accent
        case .danger:  return theme.delBg
        }
    }
}

#Preview("ToolButton") {
    HStack(spacing: 8) {
        ToolButton(icon: IconLibrary.pull, label: "Pull") {}
        ToolButton(icon: IconLibrary.pull, label: "Pull", badge: 300) {}
        ToolButton(icon: IconLibrary.history, active: true) {}
        ToolButton(icon: IconLibrary.check, label: "Commit", role: .primary) {}
        ToolButton(icon: IconLibrary.trash, label: "Drop", role: .danger) {}
    }
    .padding()
}
