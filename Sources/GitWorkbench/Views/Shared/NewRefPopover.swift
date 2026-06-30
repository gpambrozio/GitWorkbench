import SwiftUI

/// A centered, scrimmed card prompting for a name when creating a branch or tag from a commit
/// (the "Create New Branch/Tag from <sha>…" context-menu items). Mirrors ``ConfirmDiscardPopover``.
struct NewRefPopover: View {
    var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    @FocusState private var focused: Bool
    let pending: PendingRefCreation

    private var isBranch: Bool { pending.kind == .branch }
    private var title: String { isBranch ? "Create New Branch" : "Create New Tag" }
    private var icon: String { isBranch ? IconLibrary.branch : IconLibrary.tag }
    private var placeholder: String { isBranch ? "branch name" : "tag name" }
    private var actionTitle: String { isBranch ? "Create Branch" : "Create Tag" }

    private var nameBinding: Binding<String> {
        Binding(get: { store.state.pendingRefCreation?.name ?? "" },
                set: { store.setPendingRefName($0) })
    }

    private var canCreate: Bool {
        !nameBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
                .onTapGesture { store.cancelRefCreation() }
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.accentSoft)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: icon).font(.system(size: 18)).foregroundStyle(theme.accent))
                Text("\(title) from \(pending.commit.shortSHA)")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(theme.ink)
                TextField(placeholder, text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(theme.field, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(focused ? theme.accentRing : theme.sep, lineWidth: focused ? 1.5 : 1))
                    .focused($focused)
                    .onSubmit { Task { await store.confirmRefCreation() } }
                HStack(spacing: 10) {
                    capsuleButton("Cancel", fill: Color.black.opacity(0.07), fg: theme.ink) { store.cancelRefCreation() }
                    capsuleButton(actionTitle, fill: theme.accent, fg: .white) { Task { await store.confirmRefCreation() } }
                        .opacity(canCreate ? 1 : 0.5)
                        .disabled(!canCreate)
                }
            }
            .padding(20).frame(width: 360)
            .background(theme.winBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: .black.opacity(0.30), radius: 25, y: 18)
        }
        .onAppear { focused = true }
    }

    private func capsuleButton(_ title: String, fill: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(fg)
                .padding(.horizontal, 16).frame(height: 30)
                .background(fill, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
}
