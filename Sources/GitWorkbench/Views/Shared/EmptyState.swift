import SwiftUI

/// Centered empty-state: a rounded tile with an icon, a title, and an optional subtitle.
struct EmptyState: View {
    @Environment(\.workbenchTheme) private var theme
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconColor: Color? = nil

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.05))
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(iconColor ?? theme.ink3)
                )
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.ink2)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }
}

#Preview("EmptyState") {
    EmptyState(icon: IconLibrary.check, title: "Working tree clean",
               subtitle: "No changes to commit.", iconColor: Color(hex: 0x2E9E5B))
        .frame(width: 300, height: 220)
}
