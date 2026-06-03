import SwiftUI

/// The reusable git-workbench component. Observes a host-provided `GitWorkbenchStore`.
/// (Plan 3 renders the same themed skeleton as before; later plans add the real
/// toolbar/rail and the three workspace views.)
public struct GitWorkbenchView: View {
    @ObservedObject private var store: GitWorkbenchStore
    @Environment(\.colorScheme) private var colorScheme

    public init(store: GitWorkbenchStore) {
        self.store = store
    }

    private var state: WorkbenchState { store.state }
    private var configuration: WorkbenchConfiguration { store.configuration }

    private var theme: WorkbenchTheme {
        WorkbenchTheme.resolved(for: colorScheme,
                                adoptsSystemAccent: configuration.theme.adoptsSystemAccent)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if configuration.showsToolbar { toolbarSkeleton }
            HStack(spacing: 0) {
                railSkeleton
                bodySkeleton
            }
        }
        .background(theme.winBg)
        .foregroundStyle(theme.ink)
        .task { await store.reload() }
    }

    private var toolbarSkeleton: some View {
        HStack(spacing: 0) {
            Text(state.repo.repositoryName)
                .font(.system(size: 13, weight: .bold))
                .padding(.leading, 20)
                .frame(width: configuration.layout.railWidth, alignment: .leading)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) { Rectangle().fill(theme.sep).frame(width: 1) }
            Spacer(minLength: 0)
        }
        .frame(height: configuration.layout.toolbarHeight)
        .background(theme.titlebar)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }

    private var railSkeleton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WORKSPACE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(theme.ink3)
                .padding(.init(top: 14, leading: 16, bottom: 5, trailing: 16))
            Spacer()
        }
        .frame(width: configuration.layout.railWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(theme.sidebarDeep)
    }

    private var bodySkeleton: some View {
        VStack(spacing: 6) {
            Image(systemName: IconLibrary.file)
                .font(.system(size: 22))
                .foregroundStyle(theme.ink3)
            Text("Select a file to view changes")
                .font(.system(size: 12))
                .foregroundStyle(theme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.winBg)
    }
}

#Preview("Workbench shell \u{2014} light") {
    GitWorkbenchView(store: .preview)
        .frame(width: 980, height: 600)
}

#Preview("Workbench shell \u{2014} dark") {
    GitWorkbenchView(store: .preview)
        .frame(width: 980, height: 600)
        .preferredColorScheme(.dark)
}
