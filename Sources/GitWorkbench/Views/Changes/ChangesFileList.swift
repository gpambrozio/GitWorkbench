import SwiftUI

/// The scrollable Staged / Changes groups (or a clean-tree empty state).
struct ChangesFileList: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    @State private var stagedCollapsed = false
    @State private var changesCollapsed = false

    var body: some View {
        let staged = store.state.staged
        let unstaged = store.state.unstaged
        if staged.isEmpty && unstaged.isEmpty {
            EmptyState(icon: IconLibrary.check, title: "Working tree clean",
                       subtitle: "No changes to commit.", iconColor: theme.statusAdded)
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if !staged.isEmpty {
                        group(title: "Staged", count: staged.count, collapsed: $stagedCollapsed,
                              actionTitle: "Unstage all", action: { Task { await store.unstageAll() } },
                              files: staged)
                    }
                    if !unstaged.isEmpty {
                        group(title: "Changes", count: unstaged.count, collapsed: $changesCollapsed,
                              actionTitle: "Stage all", action: { Task { await store.stageAll() } },
                              files: unstaged)
                    }
                }
            }
        }
    }

    private func group(title: String, count: Int, collapsed: Binding<Bool>,
                       actionTitle: String, action: @escaping () -> Void,
                       files: [FileChange]) -> some View {
        Section {
            if !collapsed.wrappedValue {
                ForEach(files) { file in
                    FileListRow(store: store, file: file)
                        // A non-both-modified file keeps the same id (its path) when it flips between
                        // the Staged and Changes sections. In a LazyVStack with pinned headers SwiftUI
                        // reuses the moved row's subtree and leaves the StageBox stale, so fold the
                        // staged state into the identity to force a fresh row when it flips.
                        .id("\(file.isStaged ? "s" : "u"):\(file.id)")
                }
            }
        } header: {
            HStack(spacing: 6) {
                Button { collapsed.wrappedValue.toggle() } label: {
                    Image(systemName: collapsed.wrappedValue ? IconLibrary.chevronRight : IconLibrary.chevronDown)
                        .font(.system(size: 10)).foregroundStyle(theme.ink3)
                }.buttonStyle(.plain)
                Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(theme.ink3)
                Text("\(count)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.ink3)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.black.opacity(0.06), in: Capsule())
                Spacer()
                Button(actionTitle, action: action)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.accentDeep).buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(theme.sidebar)
        }
    }
}
