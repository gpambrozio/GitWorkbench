import SwiftUI

/// The stash detail pane: header (ref/message + Apply/Pop/Drop) → changed files → diff.
struct StashDetail: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    let stash: Stash

    var body: some View {
        VStack(spacing: 0) {
            header
            DetailFilesBlock(files: stash.files, selectedID: store.state.selectedStashFileID) {
                store.selectStashFile($0)
            }
            DetailDiffArea(store: store, selectedFileID: store.state.selectedStashFileID)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(stash.ref).font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accentDeep)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: Tokens.pillRadius))
                Text(stash.message).font(.system(size: 16, weight: .bold)).foregroundStyle(theme.ink).lineLimit(1)
            }
            HStack(spacing: 6) {
                Image(systemName: IconLibrary.branch).font(.system(size: 10)).foregroundStyle(theme.ink3)
                Text("on \(stash.branch)").font(.system(size: 11.5)).foregroundStyle(theme.ink2)
                Text("\u{00B7} stashed \(stash.date)").font(.system(size: 11.5)).foregroundStyle(theme.ink3)
                Spacer()
                ToolButton(icon: IconLibrary.applyStash, label: "Apply") { Task { await store.applyStash(stash.id) } }
                ToolButton(icon: IconLibrary.push, label: "Pop", role: .primary) { Task { await store.popStash(stash.id) } }
                ToolButton(icon: IconLibrary.trash, label: "Drop", role: .danger) { Task { await store.dropStash(stash.id) } }
            }
        }
        .padding(.init(top: 16, leading: 20, bottom: 14, trailing: 20))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }
}
