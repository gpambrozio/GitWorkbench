import SwiftUI
import AppKit

/// The commit detail pane: metadata (summary/body/author + copy-SHA) → changed files → diff.
///
/// The **message** (summary + body) is a resizable, scrollable region; a `RowResizeDivider` at the
/// files/diff boundary drags it. Dragging up grows the diff and shrinks the message (down to ~2 lines),
/// dragging down grows it back up to its natural height. The author row stays pinned below the message.
/// The chosen height persists via `ColumnLayout` (like the column widths). See `MessageResize`.
struct CommitDetail: View {
    @EnvironmentObject private var layout: ColumnLayout
    var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    let commit: Commit

    /// Total detail-pane height, the pinned block's height, and the message's natural height — measured
    /// live so `MessageResize` can clamp the message so the diff stays visible.
    @State private var availableHeight: CGFloat = 0
    @State private var reservedHeight: CGFloat = 0
    @State private var naturalMessageHeight: CGFloat = 0
    /// Effective message height captured when a drag starts, so cumulative translation applies to it.
    @State private var dragStart: CGFloat?

    private var messageHeight: CGFloat {
        MessageResize.height(desired: layout.commitMessageHeight, natural: naturalMessageHeight,
                             available: availableHeight, reserved: reservedHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            message
            fixedBlock
            DetailDiffArea(store: store, selectedFileID: store.state.selectedCommitFileID)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { availableHeight = $0 }
    }

    /// Summary + body, scrollable and resizable. Its natural height is measured so a short message hugs
    /// its content and a long one caps-and-scrolls.
    private var message: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(commit.summary).font(.system(size: 16, weight: .bold)).tracking(-0.2)
                    .foregroundStyle(theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                if !commit.body.isEmpty {
                    Text(commit.body).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(theme.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8).textSelection(.enabled)
                }
            }
            .padding(.init(top: 16, leading: 20, bottom: 14, trailing: 20))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { naturalMessageHeight = $0 }
        }
        .frame(height: messageHeight)
    }

    /// Everything between the message and the diff: the pinned author row, the changed-files list, and
    /// the resize handle. Measured as `reservedHeight` so the message clamp can keep the diff ≥ its min.
    private var fixedBlock: some View {
        VStack(spacing: 0) {
            author
            DetailFilesBlock(files: commit.files, selectedID: store.state.selectedCommitFileID) {
                store.selectCommitFile($0)
            }
            RowResizeDivider(
                onChanged: { translation in
                    if dragStart == nil { dragStart = messageHeight }
                    layout.commitMessageHeight = MessageResize.height(
                        desired: (dragStart ?? messageHeight) + translation,
                        natural: naturalMessageHeight, available: availableHeight, reserved: reservedHeight)
                },
                onEnded: { dragStart = nil }
            )
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { reservedHeight = $0 }
    }

    /// Pinned author/date row with the copy-SHA button — always visible, even when the message is
    /// scrolled to its minimum.
    private var author: some View {
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
                    .background(theme.neutralFill(0.06), in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain)
        }
        .padding(.init(top: 14, leading: 20, bottom: 14, trailing: 20))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }

    private func copySHA() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commit.shortSHA, forType: .string)
        store.showToast("Copied \(commit.shortSHA) to clipboard")
    }
}
