import SwiftUI

/// The diff pane: a file header (meta + stage/discard actions) over the `DiffView`, or an empty state.
struct ChangesDiffPane: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if let file = selectedFile {
                header(file)
                if let diff = store.state.currentDiff, diff.file.id == file.id {
                    DiffView(diff: diff, mode: store.state.diffMode)
                } else {
                    Spacer()
                }
            } else {
                EmptyState(icon: IconLibrary.file,
                           title: store.state.repo.files.isEmpty ? "Nothing to show \u{2014} working tree is clean"
                                                                  : "Select a file to view changes")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.winBg)
    }

    private var selectedFile: FileChange? {
        store.state.repo.files.first { $0.id == store.state.selectedFileID }
    }

    private func header(_ file: FileChange) -> some View {
        HStack(spacing: 9) {
            StatusGlyph(status: file.status, size: 16)
            Text(file.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink).lineLimit(1)
            if !file.directory.isEmpty {
                Text("\(file.directory)/").font(.system(size: 11.5)).foregroundStyle(theme.ink3).lineLimit(1)
            }
            StatChips(additions: file.additions, deletions: file.deletions)
            Rectangle().fill(theme.sep).frame(width: 1, height: 14)
            Text(file.status.label).font(.system(size: 11.5)).foregroundStyle(theme.ink3)
            Spacer(minLength: 8)
            ToolButton(icon: file.isStaged ? IconLibrary.minus : IconLibrary.plus,
                       label: file.isStaged ? "Unstage" : "Stage") { Task { await store.toggleStage(file.id) } }
            ToolButton(icon: IconLibrary.discard, label: "Discard", role: .danger) { store.requestDiscard(file.id) }
        }
        .padding(.horizontal, 16)
        .frame(height: Tokens.diffHeaderHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }
}
