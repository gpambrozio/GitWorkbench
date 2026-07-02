import SwiftUI

/// The top bar: repo name · pull/push/fetch · diff-mode control. Branch switching and the
/// History/Stashes views live in the sidebar rail, so they're not duplicated here.
struct WorkbenchToolbar: View {
    var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            Text(store.repo.repositoryName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.ink)
                .padding(.leading, 20)
                .frame(width: Tokens.railWidth, alignment: .leading)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) { Rectangle().fill(theme.sep).frame(width: 1) }

            HStack(spacing: 3) {
                ToolButton(icon: IconLibrary.pull, label: "Pull", badge: store.repo.behind) { Task { await store.pull() } }
                    .disabled(store.isBusy)
                ToolButton(icon: IconLibrary.push, label: "Push", badge: store.repo.ahead) { Task { await store.push() } }
                    .disabled(store.isBusy)
                ToolButton(icon: IconLibrary.fetch, label: "Fetch") { Task { await store.fetch() } }
                    .disabled(store.isBusy)
            }
            .padding(.leading, 14)

            Spacer(minLength: 0)

            Segmented(value: $store.diffMode, options: [
                .init(value: .unified, icon: IconLibrary.unifiedRows, accessibilityLabel: "Unified diff"),
                .init(value: .split, icon: IconLibrary.splitColumns, accessibilityLabel: "Split diff"),
            ])
            .padding(.trailing, 14)
        }
        .frame(height: Tokens.toolbarHeight)
        .background(theme.titlebar)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }
}
