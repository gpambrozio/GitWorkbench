import SwiftUI

struct WorkspaceRail: View {
    var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    /// Collapsed folders (keyed by namespaced slash-path, e.g. "L:feat" or "R:origin:feat") and the
    /// reconcile bookkeeping behind them live on the `store`, not in this view's `@State` — so the
    /// user's expanded folders survive the view being torn down and rebuilt when a host swaps the
    /// workbench out and back (a tab/session switch). See `GitWorkbenchStore.applyRailCollapseDefaults`.

    var body: some View {
        let s = store.state
        // Derived once per body pass so unrelated re-evaluations (hover, selection, scroll) don't
        // rebuild the tree; it only changes when the branch list does. The repository's default
        // branch (main/master/develop) is pinned to the top of its list.
        let localTree = makeBranchTree(s.branches,
                                       pinnedToTop: defaultBranchName(among: s.branches.map(\.name))) { $0.name }
        // Built once here (like `localTree`) so the rows and `allCollapsibleFolders` reuse each
        // remote's tree instead of rebuilding it on every body pass.
        let remoteTrees = remoteGroups(s.remoteBranches).map { group in
            RemoteTree(group: group,
                       tree: makeBranchTree(group.branches,
                                            pinnedToTop: defaultBranchName(among: group.branches.map(\.name))) { $0.name })
        }
        // A more stable repo identity than the basename `repositoryName` (two clones can share a
        // folder name): the absolute path when the host supplies a `repositoryURL`, else the basename.
        let repoID = store.configuration.repositoryURL?.path(percentEncoded: false) ?? s.repo.repositoryName
        // Changes exactly when the branch lists or current HEAD change — so the default collapse
        // state is (re)computed then and on first appearance, but not on hover/selection/scroll.
        let collapseKey = CollapseSignature(repo: repoID, head: s.repo.currentBranch,
                                            local: s.branches.map(\.id), remote: s.remoteBranches.map(\.id))
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                railHeader("WORKSPACE")
                RailItem(icon: IconLibrary.file, title: "Changes", count: s.repo.files.count,
                         selected: s.activeView == .changes) { store.select(.changes) }
                RailItem(icon: IconLibrary.history, title: "History", count: s.commits.count,
                         selected: s.activeView == .history) { store.select(.history) }
                RailItem(icon: IconLibrary.folder, title: "Stashes", count: s.stashes.count,
                         selected: s.activeView == .stashes) { store.select(.stashes) }

                railHeader("BRANCHES")
                BranchTreeRows(nodes: localTree,
                               depth: 0, keyPrefix: "L:", collapsed: store.railCollapsed,
                               toggle: { store.toggleRailFolder($0) })
                { branch, name, indent in
                    localBranchRow(branch, displayName: name, indent: indent, state: s)
                }

                if !remoteTrees.isEmpty {
                    railHeader("REMOTES")
                    ForEach(remoteTrees) { entry in
                        let remoteKey = entry.key
                        FolderRow(name: entry.group.remote, depth: 0, collapsed: store.railCollapsed.contains(remoteKey),
                                  folderKey: remoteKey)
                        {
                            store.toggleRailFolder(remoteKey)
                        }
                        if !store.railCollapsed.contains(remoteKey) {
                            BranchTreeRows(nodes: entry.tree,
                                           depth: 1, keyPrefix: "\(remoteKey):", collapsed: store.railCollapsed,
                                           toggle: { store.toggleRailFolder($0) })
                            { remote, name, indent in
                                remoteBranchRow(remote, displayName: name, indent: indent, state: s)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity) // width is set by the parent (resizable)
        .background(theme.sidebarDeep)
        // Initialize/refresh the collapse state when the branches or HEAD change (and on first
        // appearance). New folders default to collapsed; the user's own toggles are preserved.
        .onChange(of: collapseKey, initial: true) {
            store.applyRailCollapseDefaults(allFolders: allCollapsibleFolders(local: localTree, remotes: remoteTrees),
                                            currentBranch: s.repo.currentBranch,
                                            headPath: currentBranchExpansion(currentBranch: s.repo.currentBranch,
                                                                             upstream: s.repo.upstream,
                                                                             remoteBranches: s.remoteBranches),
                                            repo: repoID)
        }
    }

    /// Every collapsible folder key currently in the rail: local folders, each remote's header, and
    /// the folders inside each remote tree — namespaced exactly as `BranchTreeRows` keys them.
    private func allCollapsibleFolders(local: [BranchTreeNode<Branch>], remotes: [RemoteTree]) -> Set<String> {
        var keys = Set(folderKeys(local, keyPrefix: "L:"))
        for entry in remotes {
            keys.insert(entry.key)
            keys.formUnion(folderKeys(entry.tree, keyPrefix: "\(entry.key):"))
        }
        return keys
    }

    /// A leaf row for a local branch: click views its history, double-click switches to it. The
    /// checked-out branch is emphasized and carries a "HEAD" badge.
    private func localBranchRow(_ branch: Branch, displayName: String, indent: CGFloat, state s: WorkbenchState) -> some View {
        let isCurrent = branch.name == s.repo.currentBranch
        return RailItem(icon: IconLibrary.branch, title: displayName, count: nil,
                        selected: s.activeView == .history && branch.name == (s.historyBranch ?? s.repo.currentBranch),
                        emphasized: isCurrent, badge: isCurrent ? "HEAD" : nil,
                        ahead: branch.ahead, behind: branch.behind, indent: indent,
                        doubleAction: { Task { await store.switchBranch(to: branch) } })
        {
            Task { await store.showHistory(of: branch) }
        }
        .help("Click to view history \u{00B7} double-click to switch")
    }

    /// A leaf row for a remote-tracking branch: click views its history, double-click checks it out.
    /// The branch the current HEAD tracks is emphasized.
    private func remoteBranchRow(_ remote: RemoteBranch, displayName: String, indent: CGFloat, state s: WorkbenchState) -> some View {
        RailItem(icon: IconLibrary.branch, title: displayName, count: nil,
                 selected: s.activeView == .history && remote.id == s.historyBranch,
                 emphasized: remote.id == s.repo.upstream, indent: indent,
                 doubleAction: { Task { await store.checkoutRemoteBranch(remote) } })
        {
            Task { await store.showHistory(of: remote) }
        }
        .help("Click to view history \u{00B7} double-click to check out")
    }

    private func railHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold)).tracking(0.4)
            .foregroundStyle(theme.ink3)
            .padding(.init(top: 14, leading: 16, bottom: 5, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Remote branches grouped under their remote, preserving the provider's order (alphabetical,
    /// from `git for-each-ref`) for both remotes and the branches within each.
    private func remoteGroups(_ branches: [RemoteBranch]) -> [RemoteGroup] {
        var order: [String] = []
        var byRemote: [String: [RemoteBranch]] = [:]
        for branch in branches {
            if byRemote[branch.remote] == nil { order.append(branch.remote) }
            byRemote[branch.remote, default: []].append(branch)
        }
        return order.map { RemoteGroup(remote: $0, branches: byRemote[$0] ?? []) }
    }
}

private struct RemoteGroup {
    let remote: String
    let branches: [RemoteBranch]
}

/// A remote group paired with its built branch tree, so the tree is computed once per body pass and
/// reused by both the rendered rows and `allCollapsibleFolders` (rather than rebuilt in each).
private struct RemoteTree: Identifiable {
    let group: RemoteGroup
    let tree: [BranchTreeNode<RemoteBranch>]
    /// Namespaced collapse key for this remote's header folder, e.g. "R:origin".
    var key: String { "R:\(group.remote)" }
    var id: String { key }
}

/// Identity of the inputs that determine the default collapse state. Equatable so `onChange` fires
/// only when the branches or current HEAD actually change — not on every body re-evaluation.
private struct CollapseSignature: Equatable {
    let repo: String
    let head: String
    let local: [String]
    let remote: [String]
}

/// Renders one branch tree (local, or a single remote's branches) as indented, collapsible rows.
/// Folders call `toggle` with their namespaced key; leaves are built by the caller-supplied `leaf`
/// closure so the same recursion serves both the local-branch and remote-branch sections.
private struct BranchTreeRows<Leaf, Content: View>: View {
    let nodes: [BranchTreeNode<Leaf>]
    let depth: Int
    /// Prepended to each folder's path to keep collapse keys unique across the local tree and every
    /// remote tree (which can share folder names like "feat").
    let keyPrefix: String
    let collapsed: Set<String>
    let toggle: (String) -> Void
    let leaf: (Leaf, _ displayName: String, _ indent: CGFloat) -> Content

    var body: some View {
        ForEach(nodes) { node in
            switch node.kind {
            case let .leaf(value):
                leaf(value, node.name, leafIndent(depth))
            case let .folder(children):
                let key = keyPrefix + node.id
                let isCollapsed = collapsed.contains(key)
                FolderRow(name: node.name, depth: depth, collapsed: isCollapsed, folderKey: key) { toggle(key) }
                if !isCollapsed {
                    BranchTreeRows(nodes: children, depth: depth + 1, keyPrefix: keyPrefix,
                                   collapsed: collapsed, toggle: toggle, leaf: leaf)
                }
            }
        }
    }
}

/// Leading inset for a leaf row at `depth`, so its branch icon lines up under the folder icons at
/// the same depth (one indent step per level, plus the chevron column folders reserve).
private func leafIndent(_ depth: Int) -> CGFloat {
    CGFloat(depth) * Tokens.railIndentStep + Tokens.railChevronWidth + 8
}

/// A collapsible folder row: disclosure chevron + folder icon + the path segment. A `Button` (like
/// `RailItem`) so it's reachable by keyboard and VoiceOver. Mirrors `RailItem`'s metrics so folders
/// and branches share a baseline.
private struct FolderRow: View {
    @Environment(\.workbenchTheme) private var theme
    @State private var hover = false
    let name: String
    let depth: Int
    let collapsed: Bool
    /// Namespaced collapse key (e.g. "L:fix" or "R:origin"). Doubles as the row's accessibility
    /// identifier ("branch-folder-<key>") so a host's UI tests can target one specific folder.
    let folderKey: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) { label }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .padding(.horizontal, Tokens.railInsetH)
            .help(collapsed ? "Click to expand" : "Click to collapse")
            .accessibilityIdentifier("branch-folder-\(folderKey)")
    }

    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: collapsed ? IconLibrary.chevronRight : IconLibrary.chevronDown)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.ink3)
                .frame(width: Tokens.railChevronWidth)
            Image(systemName: IconLibrary.folder)
                .font(.system(size: 12))
                .foregroundStyle(theme.ink2)
            Text(name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
        }
        .padding(.leading, 8 + CGFloat(depth) * Tokens.railIndentStep).padding(.trailing, 8)
        .frame(height: Tokens.railRowHeight)
        .frame(maxWidth: .infinity)
        .background(hover ? Color.black.opacity(0.05) : .clear,
                    in: RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct RailItem: View {
    @Environment(\.workbenchTheme) private var theme
    @State private var hover = false
    let icon: String
    let title: String
    var count: Int?
    let selected: Bool
    /// Bold + accent treatment for the active row (the current local branch, or the remote the
    /// current branch tracks).
    var emphasized: Bool = false
    /// Optional trailing badge (e.g. "HEAD" on the checked-out branch).
    var badge: String? = nil
    /// Divergence from upstream, shown before the badge as "{ahead}↑ {behind}↓". Both default to 0
    /// (hidden) so non-branch rows leave them off. See `AheadBehindBadge`.
    var ahead: Int = 0
    var behind: Int = 0
    var indent: CGFloat = 0
    /// Optional double-click action. When set, a single click runs `action` and a double-click runs
    /// this — used for branch rows (click = view history, double-click = switch).
    var doubleAction: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Group {
            if let doubleAction {
                label
                    .onTapGesture(count: 2, perform: doubleAction)
                    .onTapGesture(count: 1, perform: action)
            } else {
                Button(action: action) { label }.buttonStyle(.plain)
            }
        }
        .onHover { hover = $0 }
        .padding(.horizontal, Tokens.railInsetH)
    }

    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(selected ? .white : (emphasized ? theme.accent : theme.ink2))
            Text(title)
                .font(.system(size: 12.5, weight: emphasized ? .bold : .medium))
                .foregroundStyle(selected ? .white : theme.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            AheadBehindBadge(ahead: ahead, behind: behind, onAccent: selected)
            if let badge {
                Text(badge)
                    .font(.system(size: 9.5, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()   // never wrap "HEAD" to two lines when the ahead/behind badge tightens the row
                    .foregroundStyle(selected ? .white : theme.accentDeep)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(selected ? Color.white.opacity(0.22) : theme.accentSoft,
                                in: RoundedRectangle(cornerRadius: 4))
            }
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : theme.ink3)
            }
        }
        .padding(.leading, 8 + indent).padding(.trailing, 8)
        .frame(height: Tokens.railRowHeight)
        .frame(maxWidth: .infinity)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous))
        .contentShape(Rectangle())
    }

    private var rowBackground: Color {
        if selected { return theme.accent }
        if hover { return Color.black.opacity(0.05) }
        return .clear
    }
}
