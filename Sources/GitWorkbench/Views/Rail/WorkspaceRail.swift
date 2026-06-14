import SwiftUI

struct WorkspaceRail: View {
    var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        let s = store.state
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
                ForEach(s.branches) { branch in
                    let isCurrent = branch.name == s.repo.currentBranch
                    RailItem(icon: IconLibrary.branch, title: branch.name, count: nil,
                             selected: s.activeView == .history && branch.name == (s.historyBranch ?? s.repo.currentBranch),
                             emphasized: isCurrent, badge: isCurrent ? "HEAD" : nil,
                             doubleAction: { Task { await store.switchBranch(to: branch) } }) {
                        Task { await store.showHistory(of: branch) }
                    }
                    .help("Click to view history \u{00B7} double-click to switch")
                }

                if !s.remoteBranches.isEmpty {
                    railHeader("REMOTES")
                    ForEach(remoteGroups(s.remoteBranches), id: \.remote) { group in
                        remoteHeader(group.remote)
                        ForEach(group.branches) { remote in
                            RailItem(icon: IconLibrary.branch, title: remote.name, count: nil,
                                     selected: s.activeView == .history && remote.id == s.historyBranch,
                                     emphasized: remote.id == s.repo.upstream, indent: 26,
                                     doubleAction: { Task { await store.checkoutRemoteBranch(remote) } }) {
                                Task { await store.showHistory(of: remote) }
                            }
                            .help("Click to view history \u{00B7} double-click to check out")
                        }
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)   // width is set by the parent (resizable)
        .background(theme.sidebarDeep)
    }

    private func railHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold)).tracking(0.4)
            .foregroundStyle(theme.ink3)
            .padding(.init(top: 14, leading: 16, bottom: 5, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A non-interactive sub-header naming a remote (e.g. "origin") above its branches. Mirrors a
    /// `RailItem`'s look but takes no taps and shows no hover feedback — it's a label, not a control.
    private func remoteHeader(_ name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: IconLibrary.folder)
                .font(.system(size: 12))
                .foregroundStyle(theme.ink2)
            Text(name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
        }
        .padding(.leading, 8).padding(.trailing, 8)
        .frame(height: Tokens.railRowHeight)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Tokens.railInsetH)
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
            if let badge {
                Text(badge)
                    .font(.system(size: 9.5, weight: .bold))
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
