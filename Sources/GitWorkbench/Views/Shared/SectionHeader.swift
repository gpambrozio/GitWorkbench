import SwiftUI

/// Uppercase section header with an optional count badge and a trailing action link.
struct SectionHeader: View {
    @Environment(\.workbenchTheme) private var theme
    let title: String
    var count: Int? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(theme.ink3)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.ink3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.06), in: Capsule())
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accentDeep)
                    .buttonStyle(.plain)
            }
        }
        .padding(.init(top: 5, leading: 14, bottom: 5, trailing: 16))
    }
}

#Preview("SectionHeader") {
    VStack(spacing: 0) {
        SectionHeader(title: "Staged", count: 3, actionTitle: "Unstage all") {}
        SectionHeader(title: "Workspace")
    }
    .padding(.vertical)
}
