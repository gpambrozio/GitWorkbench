import SwiftUI

/// The reusable git-workbench component: toolbar + rail + active workspace view, themed and toasted.
public struct GitWorkbenchView: View {
    private let store: GitWorkbenchStore
    @State private var layout: ColumnLayout
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.repositorySummaryObserver) private var summaryObserver

    public init(store: GitWorkbenchStore) {
        self.store = store
        _layout = State(initialValue: ColumnLayout(configuration: store.configuration))
    }

    private var configuration: WorkbenchConfiguration { store.configuration }
    private var theme: WorkbenchTheme {
        let base = colorScheme == .dark ? configuration.darkTheme : configuration.theme
        return base.adoptsSystemAccent ? base.adoptingSystemAccent() : base
    }

    public var body: some View {
        @Bindable var layout = layout
        VStack(spacing: 0) {
            if configuration.showsToolbar { WorkbenchToolbar(store: store) }
            HStack(spacing: 0) {
                WorkspaceRail(store: store)
                    .frame(width: layout.railWidth)
                ResizeDivider(width: $layout.railWidth, range: layout.railRange)
                body(for: store.activeView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .environment(layout)
        }
        .background(theme.winBg)
        .foregroundStyle(theme.ink)
        .workbenchTheme(theme)
        // Resets descendant state (e.g. WorkspaceRail's) when a host swaps stores at the same
        // view identity (e.g. LiveDemo's Open…) with a different persistence key. A self-applied
        // `.id` doesn't reset this view's own @State — see the `layout` re-seed below for that.
        .id(configuration.persistenceKey)
        // Self-applied `.id` above can't reset this view's own @State layout, so re-seed it
        // explicitly when a host swaps stores with a different persistence key, so drags persist
        // under the new key.
        .onChange(of: store.configuration.persistenceKey) { layout = ColumnLayout(configuration: store.configuration) }
        .overlay(alignment: .bottom) { toastOverlay }
        // Drive the host observer off `store.summary` so it fires only once a load has
        // completed — never with the pre-load placeholder — matching the headless
        // `store.summary` semantics.
        .onChange(of: store.summary, initial: true) { _, summary in
            if let summary { summaryObserver.onChange?(summary) }
        }
        .task { await store.reload() }
    }

    @ViewBuilder
    private func body(for view: WorkspaceView) -> some View {
        switch view {
        case .changes: ChangesBody(store: store)
        case .history: HistoryBody(store: store)
        case .stashes: StashBody(store: store)
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        ZStack {
            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(.bottom, Tokens.toastBottomInset)
                    .transition(.opacity)
                    .task(id: toast.id) {
                        guard toast.style != .progress else { return }
                        try? await Task.sleep(for: .seconds(2.2))
                        store.dismissToast()
                    }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.toast)
    }
}

#Preview("Workbench — light") {
    GitWorkbenchView(store: .preview).frame(width: 1100, height: 680)
}

#Preview("Workbench — dark") {
    GitWorkbenchView(store: .preview).frame(width: 1100, height: 680).preferredColorScheme(.dark)
}
