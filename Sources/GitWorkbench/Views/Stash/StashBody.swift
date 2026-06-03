import SwiftUI

/// The Stash workspace: stash list (360) + stash detail (or empty states).
struct StashBody: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: IconLibrary.folder).font(.system(size: 12)).foregroundStyle(theme.ink3)
                    Text("STASHES").font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(theme.ink3)
                    Text("\(store.state.stashes.count)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(theme.ink3).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.black.opacity(0.06), in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 14).frame(height: 44)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }

                if store.state.stashes.isEmpty {
                    EmptyState(icon: IconLibrary.folder, title: "No stashes",
                               subtitle: "Shelved changes show up here.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.state.stashes) { StashRow(store: store, stash: $0) }
                        }
                    }
                }
            }
            .frame(width: Tokens.historyListWidth)
            .background(theme.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(theme.sep).frame(width: 1) }

            Group {
                if let stash = store.state.stashes.first(where: { $0.id == store.state.selectedStashID }) {
                    StashDetail(store: store, stash: stash)
                } else {
                    EmptyState(icon: IconLibrary.folder, title: "Select a stash",
                               subtitle: "Choose a stash to see its changes.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.winBg)
        }
    }
}
