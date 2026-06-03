import SwiftUI

/// One row in a commit/stash detail's changed-files list.
struct DetailFileRow: View {
    @Environment(\.workbenchTheme) private var theme
    @State private var hover = false
    let file: FileChange
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                StatusGlyph(status: file.status, size: 15)
                Text(file.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(theme.ink).lineLimit(1)
                if !file.directory.isEmpty {
                    Text(file.directory).font(.system(size: 11.5)).foregroundStyle(theme.ink3)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 6)
                StatChips(additions: file.additions, deletions: file.deletions)
            }
            .padding(.horizontal, 16)
            .frame(height: Tokens.detailFileRowHeight)
            .frame(maxWidth: .infinity)
            .background(selected ? theme.accentSoft : (hover ? Color.black.opacity(0.03) : .clear))
            .overlay(alignment: .leading) { if selected { Rectangle().fill(theme.accent).frame(width: 2) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// The "N changed files" header + the rows.
struct DetailFilesBlock: View {
    @Environment(\.workbenchTheme) private var theme
    let files: [FileChange]
    let selectedID: FileChange.ID?
    let onSelect: (FileChange.ID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("\(files.count) changed \(files.count == 1 ? "file" : "files")")
                .font(.system(size: 10.5, weight: .bold)).tracking(0.4).textCase(.uppercase)
                .foregroundStyle(theme.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 6)
            ForEach(files) { file in
                DetailFileRow(file: file, selected: file.id == selectedID) { onSelect(file.id) }
            }
        }
        .background(theme.sidebar)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }
}

/// A detail pane's diff area: the guarded `DiffView` for the selected file, or an empty state.
struct DetailDiffArea: View {
    @ObservedObject var store: GitWorkbenchStore
    let selectedFileID: FileChange.ID?

    var body: some View {
        if let diff = store.state.currentDiff, diff.file.id == selectedFileID {
            DiffView(diff: diff, mode: store.state.diffMode)
        } else {
            EmptyState(icon: IconLibrary.file, title: "Select a file to view changes")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
