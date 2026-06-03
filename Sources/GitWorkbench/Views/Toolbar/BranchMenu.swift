import SwiftUI

/// The "switch branch" popover content.
struct BranchMenu: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SWITCH BRANCH")
                .font(.system(size: 11, weight: .bold)).tracking(0.4)
                .foregroundStyle(theme.ink3)
                .padding(.init(top: 12, leading: 14, bottom: 6, trailing: 14))

            ForEach(store.state.branches) { branch in
                BranchMenuRow(
                    branch: branch,
                    isCurrent: branch.name == store.state.repo.currentBranch,
                    ahead: store.state.repo.ahead,
                    behind: store.state.repo.behind
                ) { Task { await store.switchBranch(to: branch) } }
            }
        }
        .padding(.bottom, 6)
        .frame(width: 280)
    }
}

private struct BranchMenuRow: View {
    @Environment(\.workbenchTheme) private var theme
    @State private var hover = false
    let branch: Branch
    let isCurrent: Bool
    let ahead: Int
    let behind: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: IconLibrary.branch)
                    .foregroundStyle(isCurrent ? theme.accent : theme.ink3)
                Text(branch.name)
                    .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                if isCurrent {
                    Text("\(ahead)\u{2191} \(behind)\u{2193}")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(theme.ink3)
                    Image(systemName: IconLibrary.check).foregroundStyle(theme.accent).font(.system(size: 11))
                }
            }
            .padding(.horizontal, 14).frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(hover ? Color.black.opacity(0.05) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
