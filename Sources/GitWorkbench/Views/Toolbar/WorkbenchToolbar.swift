import SwiftUI

/// The top bar: repo name · pull/push/fetch · diff-mode control. Branch switching and the
/// History/Stashes views live in the sidebar rail, so they're not duplicated here.
struct WorkbenchToolbar: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        let s = store.state
        HStack(spacing: 0) {
            Text(s.repo.repositoryName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.ink)
                .padding(.leading, 20)
                .frame(width: Tokens.railWidth, alignment: .leading)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) { Rectangle().fill(theme.sep).frame(width: 1) }

            HStack(spacing: 3) {
                ToolButton(icon: IconLibrary.pull, label: "Pull", badge: s.repo.behind) { Task { await store.pull() } }
                    .disabled(s.isBusy)
                ToolButton(icon: IconLibrary.push, label: "Push", badge: s.repo.ahead) { Task { await store.push() } }
                    .disabled(s.isBusy)
                ToolButton(icon: IconLibrary.fetch, label: "Fetch") { Task { await store.fetch() } }
                    .disabled(s.isBusy)
            }
            .padding(.leading, 14)

            Spacer(minLength: 0)

            Segmented(value: diffMode, options: [
                .init(value: .unified, icon: IconLibrary.unifiedRows),
                .init(value: .split, icon: IconLibrary.splitColumns),
            ])
            .padding(.trailing, 14)
        }
        .frame(height: Tokens.toolbarHeight)
        .background(theme.titlebar)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }

    private var diffMode: Binding<DiffMode> {
        Binding(get: { store.state.diffMode }, set: { store.setDiffMode($0) })
    }
}
