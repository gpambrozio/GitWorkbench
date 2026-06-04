import SwiftUI

/// The History workspace: commit list (360) + commit detail.
struct HistoryBody: View {
    @ObservedObject var store: GitWorkbenchStore
    @EnvironmentObject private var layout: ColumnLayout
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: IconLibrary.history).font(.system(size: 12)).foregroundStyle(theme.ink3)
                    Text("HISTORY").font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(theme.ink3)
                    Text("\(store.state.commits.count)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(theme.ink3).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.black.opacity(0.06), in: Capsule())
                    Spacer()
                    BranchPill(name: store.state.historyBranch ?? store.state.repo.currentBranch,
                               dim: true, showsChevron: false, height: 24)
                }
                .padding(.horizontal, 14).frame(height: 44)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }

                if store.state.isLoadingHistory {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading history\u{2026}").font(.system(size: 11.5)).foregroundStyle(theme.ink3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.state.commits) { CommitGraphRow(store: store, commit: $0) }
                        }
                    }
                }
            }
            .frame(width: layout.historyListWidth)
            .background(theme.sidebar)

            ResizeDivider(width: $layout.historyListWidth, range: layout.historyListRange)

            Group {
                if let commit = store.state.commits.first(where: { $0.id == store.state.selectedCommitID }) {
                    CommitDetail(store: store, commit: commit)
                } else {
                    EmptyState(icon: IconLibrary.history, title: "Select a commit",
                               subtitle: "Choose a commit to see its details.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.winBg)
        }
    }
}
