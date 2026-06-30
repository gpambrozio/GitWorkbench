import SwiftUI

/// A centered, scrimmed confirm card for the irreversible "Reset HEAD (Hard)" action, which
/// discards all staged and unstaged changes. Mirrors ``ConfirmDiscardPopover``.
struct ConfirmResetPopover: View {
    var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    let commit: Commit

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
                .onTapGesture { store.cancelHardReset() }
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.delBg)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: IconLibrary.discard).font(.system(size: 18)).foregroundStyle(theme.delInk))
                Text("Hard reset to \(commit.shortSHA)?")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(theme.ink)
                Text("This moves HEAD and permanently discards all staged and unstaged changes. You can\u{2019}t undo this.")
                    .font(.system(size: 12.5)).foregroundStyle(theme.ink2).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    capsuleButton("Cancel", fill: Color.black.opacity(0.07), fg: theme.ink) { store.cancelHardReset() }
                    capsuleButton("Discard & Reset", fill: theme.statusDeleted, fg: .white) { Task { await store.confirmHardReset() } }
                }
            }
            .padding(20).frame(width: 360)
            .background(theme.winBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: .black.opacity(0.30), radius: 25, y: 18)
        }
    }

    private func capsuleButton(_ title: String, fill: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(fg)
                .padding(.horizontal, 16).frame(height: 30)
                .background(fill, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
}
