import SwiftUI

/// The reusable git-workbench component: toolbar + rail + active workspace view, themed and toasted.
public struct GitWorkbenchView: View {
    @ObservedObject private var store: GitWorkbenchStore
    @Environment(\.colorScheme) private var colorScheme

    public init(store: GitWorkbenchStore) {
        self.store = store
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
                body(for: store.state.activeView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        case .changes: placeholder(IconLibrary.file, "Changes")
        case .history: placeholder(IconLibrary.history, "History")
        case .stashes: placeholder(IconLibrary.folder, "Stashes")
        }
    }

    // Temporary — replaced by the real Changes/History/Stash views in Plans 7–8.
    private func placeholder(_ icon: String, _ title: String) -> some View {
        EmptyState(icon: icon, title: title, subtitle: "View coming in the next plan.")
            .background(theme.winBg)
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
