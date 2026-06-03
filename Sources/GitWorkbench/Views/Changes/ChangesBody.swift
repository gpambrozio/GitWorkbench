import SwiftUI

/// The Changes workspace: file-list + composer pane (320), then the diff pane; discard confirm overlays.
struct ChangesBody: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ChangesFileList(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                CommitComposer(store: store)
            }
            .frame(width: Tokens.changesListWidth)
            .background(theme.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(theme.sep).frame(width: 1) }

            ChangesDiffPane(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay { if let file = store.state.pendingDiscard { ConfirmDiscardPopover(store: store, file: file) } }
    }
}
