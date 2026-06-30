import SwiftUI
import AppKit

/// A commit list row: graph column (line + node) + summary/refs + author/relative/sha.
struct CommitGraphRow: View {
    var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    @State private var hover = false
    let commit: Commit

    var body: some View {
        let selected = store.state.selectedCommitID == commit.id
        HStack(spacing: 0) {
            ZStack {
                Rectangle().fill(selected ? .white : theme.sepStrong).frame(width: 2).frame(maxHeight: .infinity)
                Circle().fill(selected ? .white : theme.winBg)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(selected ? .white : theme.accent, lineWidth: 2))
            }
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(commit.summary).font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(selected ? .white : theme.ink).lineLimit(1)
                    ForEach(Array(commit.refs.enumerated()), id: \.offset) { _, ref in
                        RefPill(ref: ref, selected: selected)
                    }
                }
                HStack(spacing: 5) {
                    Avatar(initials: commit.authorInitials, size: 15, hue: authorHue(commit.authorInitials))
                    Text(commit.authorName).font(.system(size: 11))
                        .foregroundStyle(selected ? Color.white.opacity(0.9) : theme.ink2)
                    Text("\u{00B7} \(commit.relativeDate)").font(.system(size: 11))
                        .foregroundStyle(selected ? Color.white.opacity(0.7) : theme.ink3)
                    Spacer(minLength: 6)
                    Text(commit.shortSHA).font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(selected ? Color.white.opacity(0.7) : theme.ink3)
                }
            }
            .padding(.init(top: 9, leading: 2, bottom: 9, trailing: 14))
        }
        .frame(maxWidth: .infinity)
        .background(selected ? theme.accent : (hover ? Color.black.opacity(0.04) : .clear))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { Task { await store.selectCommit(commit.id) } }
        .onHover { hover = $0 }
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var contextMenu: some View {
        let sha = commit.shortSHA
        Button("Copy Commit Hash to Clipboard") { copy(commit.id, label: "commit hash") }
        Button("Copy Commit Message to Clipboard") { copy(fullMessage, label: "commit message") }
        Divider()
        Button("Check Out \u{201C}\(sha)\u{201D}") { Task { await store.checkout(commit) } }
        Menu("Reset HEAD to \u{201C}\(sha)\u{201D}") {
            Button("Soft \u{2014} keep all changes staged") { Task { await store.resetHEAD(to: commit, mode: .soft) } }
            Button("Mixed \u{2014} keep changes, unstaged") { Task { await store.resetHEAD(to: commit, mode: .mixed) } }
            Button("Hard \u{2014} discard all changes") { Task { await store.resetHEAD(to: commit, mode: .hard) } }
        }
        Divider()
        Button("Revert \u{201C}\(sha)\u{201D}") { Task { await store.revert(commit) } }
        Button("Cherry-Pick \u{201C}\(sha)\u{201D}") { Task { await store.cherryPick(commit) } }
        Divider()
        Button("Create New Branch from \u{201C}\(sha)\u{201D}\u{2026}") { store.requestCreateBranch(at: commit) }
        Button("Create New Tag from \u{201C}\(sha)\u{201D}\u{2026}") { store.requestCreateTag(at: commit) }
    }

    /// The full commit message: summary plus body, matching what `git log` shows.
    private var fullMessage: String {
        commit.body.isEmpty ? commit.summary : "\(commit.summary)\n\n\(commit.body)"
    }

    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        store.showToast("Copied \(label) to clipboard")
    }
}
