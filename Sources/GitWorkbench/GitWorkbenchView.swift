import SwiftUI

/// The reusable git-workbench component: toolbar + rail + active workspace view, themed and toasted.
public struct GitWorkbenchView: View {
    @ObservedObject private var store: GitWorkbenchStore
    @StateObject private var layout: ColumnLayout
    @Environment(\.colorScheme) private var colorScheme

    public init(store: GitWorkbenchStore) {
        self.store = store
        _layout = StateObject(wrappedValue: ColumnLayout(configuration: store.configuration))
    }

    private var configuration: WorkbenchConfiguration { store.configuration }
    private var theme: WorkbenchTheme {
        WorkbenchTheme.resolved(for: colorScheme,
                                adoptsSystemAccent: configuration.theme.adoptsSystemAccent)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if configuration.showsToolbar { WorkbenchToolbar(store: store) }
            HStack(spacing: 0) {
                WorkspaceRail(store: store)
                    .frame(width: layout.railWidth)
                ResizeDivider(width: $layout.railWidth, range: layout.railRange)
                body(for: store.state.activeView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .environmentObject(layout)
        }
        .background(theme.winBg)
        .foregroundStyle(theme.ink)
        .workbenchTheme(theme)
        .overlay(alignment: .bottom) { toastOverlay }
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
        if let toast = store.state.toast {
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
}

#Preview("Workbench — light") {
    GitWorkbenchView(store: .preview).frame(width: 1100, height: 680)
}

#Preview("Workbench — dark") {
    GitWorkbenchView(store: .preview).frame(width: 1100, height: 680).preferredColorScheme(.dark)
}
