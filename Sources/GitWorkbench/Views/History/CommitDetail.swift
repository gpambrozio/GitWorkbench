import SwiftUI
import AppKit

/// The commit detail pane: metadata (summary/body/author + copy-SHA) → changed files → diff.
struct CommitDetail: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    let commit: Commit

    var body: some View {
        VStack(spacing: 0) {
            metadata
            DetailFilesBlock(files: commit.files, selectedID: store.state.selectedCommitFileID) {
                store.selectCommitFile($0)
            }
            DetailDiffArea(store: store, selectedFileID: store.state.selectedCommitFileID)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(commit.summary).font(.system(size: 16, weight: .bold)).tracking(-0.2)
                .foregroundStyle(theme.ink).frame(maxWidth: .infinity, alignment: .leading)
            if !commit.body.isEmpty {
                Text(commit.body).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(theme.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8).textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Avatar(initials: commit.authorInitials, size: 26, hue: authorHue(commit.authorInitials))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(commit.authorName).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.ink)
                        Text("<\(commit.authorEmail)>").font(.system(size: 11.5)).foregroundStyle(theme.ink3)
                    }
                    Text("committed \(commit.date)").font(.system(size: 11.5)).foregroundStyle(theme.ink3)
                }
                Spacer()
                Button { copySHA() } label: {
                    HStack(spacing: 5) { Image(systemName: IconLibrary.copy); Text(commit.shortSHA) }
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.ink2)
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }
            .padding(.top, 14)
        }
        .padding(.init(top: 16, leading: 20, bottom: 14, trailing: 20))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }

    private func copySHA() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commit.shortSHA, forType: .string)
        store.showToast("Copied \(commit.shortSHA) to clipboard")
    }
}
