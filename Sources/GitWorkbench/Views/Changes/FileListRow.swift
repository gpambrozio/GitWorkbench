import SwiftUI

/// One changed-file row: stage box · status glyph · name · dir · (stats | hover-discard).
struct FileListRow: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    @Environment(\.changesFileInteractions) private var interactions
    @State private var hover = false
    @State private var popover: PopoverContent?
    let file: FileChange

    /// Identifiable box so the host's right-click popover content can drive `.popover(item:)`.
    private struct PopoverContent: Identifiable {
        let id = UUID()
        let view: AnyView
    }

    /// The clicked file's URL handed to the host's custom-action callbacks (absolute when the host set
    /// `WorkbenchConfiguration.repositoryURL`, otherwise path-only).
    private var fileURL: URL { file.url(relativeTo: store.configuration.repositoryURL) }

    var body: some View {
        let selected = store.state.selectedFileID == file.id
        HStack(spacing: 8) {
            StageBox(checked: file.isStaged)
                .contentShape(Rectangle())
                .onTapGesture { Task { await store.toggleStage(file.id) } }
            StatusGlyph(status: file.status, selected: selected, size: 15)
            Text(file.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(selected ? .white : theme.ink)
                .lineLimit(1).layoutPriority(1)
            if !file.directory.isEmpty {
                Text(file.directory)
                    .font(.system(size: 11.5))
                    .foregroundStyle(selected ? Color.white.opacity(0.7) : theme.ink3)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            // Stats / discard get top priority and a fixed size so they stay visible as the column
            // narrows — the name (priority 1) and path (priority 0) truncate instead.
            trailing(selected: selected)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
        }
        .padding(.horizontal, 12)
        .frame(height: Tokens.changesRowHeight)
        .frame(maxWidth: .infinity)
        .background(rowBackground(selected: selected))
        .contentShape(Rectangle())
        .onTapGesture { store.select(file: file.id) }
        .onHover { hover = $0 }
        .overlay { mouseCatcher }
        .popover(item: $popover, arrowEdge: .trailing) { $0.view }
    }

    /// The opt-in right-click / double-click catcher — installed only when the host wired up a handler,
    /// so default behavior is untouched. Right-click fires the action and/or opens the host popover.
    @ViewBuilder private var mouseCatcher: some View {
        if interactions.isActive {
            ChangesMouseCatcher(
                onRightClick: interactions.handlesRightClick ? { handleRightClick() } : nil,
                onDoubleClick: interactions.onDoubleClick != nil ? { handleDoubleClick() } : nil
            )
        }
    }

    private func handleRightClick() {
        let url = fileURL
        interactions.onRightClick?(url)
        if let make = interactions.rightClickPopover, let view = make(url) {
            popover = PopoverContent(view: view)
        }
    }

    private func handleDoubleClick() {
        interactions.onDoubleClick?(fileURL)
    }

    @ViewBuilder private func trailing(selected: Bool) -> some View {
        if hover {
            Button { store.requestDiscard(file.id) } label: {
                Image(systemName: IconLibrary.discard)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? .white : theme.ink2)
                    .frame(width: 20, height: 20)
                    .background(selected ? Color.white.opacity(0.18) : Color.black.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        } else {
            stats(selected: selected)
        }
    }

    @ViewBuilder private func stats(selected: Bool) -> some View {
        // On a selected (accent) row, render the counts in white for contrast.
        if selected {
            HStack(spacing: 6) {
                if file.additions > 0 { Text("+\(file.additions)") }
                if file.deletions > 0 { Text("\u{2212}\(file.deletions)") }
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
        } else {
            StatChips(additions: file.additions, deletions: file.deletions)
        }
    }

    private func rowBackground(selected: Bool) -> Color {
        if selected { return theme.accent }
        if hover { return Color.black.opacity(0.04) }
        return .clear
    }
}
