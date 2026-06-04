import SwiftUI

struct WorkspaceRail: View {
    @ObservedObject var store: GitWorkbenchStore
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
                    RailItem(icon: IconLibrary.branch, title: branch.name, count: nil,
                             selected: false, current: branch.name == s.repo.currentBranch,
                             activateOnDoubleClick: true) {
                        Task { await store.switchBranch(to: branch) }
                    }
                    .help("Double-click to switch to \(branch.name)")
                }

                railHeader("REMOTES")
                RailItem(icon: IconLibrary.folder, title: "origin", count: nil, selected: false) {}
                if let upstream = s.repo.upstream {
                    RailItem(icon: IconLibrary.branch, title: upstream, count: nil, selected: false, indent: 26) {}
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
}

private struct RailItem: View {
    @Environment(\.workbenchTheme) private var theme
    @State private var hover = false
    let icon: String
    let title: String
    var count: Int?
    let selected: Bool
    var current: Bool = false
    var indent: CGFloat = 0
    /// When true the row activates on double-click (single clicks do nothing) — used for branches so a
    /// stray click doesn't switch. Default rows activate on a single click.
    var activateOnDoubleClick: Bool = false
    let action: () -> Void

    var body: some View {
        Group {
            if activateOnDoubleClick {
                label.onTapGesture(count: 2, perform: action)
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
                .foregroundStyle(selected ? .white : (current ? theme.accent : theme.ink2))
            Text(title)
                .font(.system(size: 12.5, weight: current ? .bold : .medium))
                .foregroundStyle(selected ? .white : theme.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            if current && !selected {
                Text("HEAD")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(theme.accentDeep)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 4))
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
