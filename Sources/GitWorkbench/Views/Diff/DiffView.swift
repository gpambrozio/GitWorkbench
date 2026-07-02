import SwiftUI
import AppKit

/// Renders a `FileDiff` unified or split, with deleted-file and binary special cases.
struct DiffView: View {
    @Environment(\.workbenchTheme) private var theme
    let diff: FileDiff
    let mode: DiffMode

    var body: some View {
        Group {
            if let content = diff.binaryContent {
                // Image / PDF viewer. `.id` resets the comparison controls' local state per file.
                BinaryDiffView(content: content, file: diff.file).id(diff.file.id)
            } else if diff.isBinary {
                BinaryPlaceholder(file: diff.file)
            } else if diff.file.status == .deleted {
                scrollingCode(minWidth: contentMinWidth) { deletedRows }
            } else if mode == .split {
                // Split owns its own horizontal scrolling: gutters/signs/divider/headers stay pinned and
                // only the code columns slide, synced across both sides. `.id` resets that horizontal
                // offset (and its scroll catcher) whenever the file changes.
                SplitDiffBody(diff: diff).id(diff.file.id)
            } else {
                scrollingCode(minWidth: contentMinWidth) { unifiedRows }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.winBg)
    }

    /// Vertical + horizontal scroll for the single-column (unified / deleted) layouts. The content is
    /// at least as wide as the longest line (so long lines scroll instead of truncating) and at least
    /// the pane width (so short diffs still fill it). Separate `minHeight` top-aligns short diffs.
    private func scrollingCode<V: View>(minWidth: CGFloat, @ViewBuilder _ inner: () -> V) -> some View {
        let inner = inner()
        return GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                inner.frame(width: max(minWidth, geo.size.width), alignment: .topLeading)
                    .frame(minHeight: geo.size.height, alignment: .topLeading)
            }
        }
    }

    private var unifiedRows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(diff.hunks) { hunk in
                HunkHeaderBand(text: hunk.header)
                ForEach(hunk.lines) { UnifiedDiffRow(line: $0) }
            }
        }
    }

    // Deleted file: all lines as unified rows, no headers, dimmed (diff.jsx).
    private var deletedRows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(diff.hunks) { hunk in
                ForEach(hunk.lines) { UnifiedDiffRow(line: $0) }
            }
        }
        .opacity(0.92)
    }

    /// Total content width for the single-column layouts = fixed gutters + sign + the code column
    /// (+ a clip-safety buffer).
    private var contentMinWidth: CGFloat {
        let code = DiffMetrics.maxCodeWidth(diff) + 28
        return Tokens.unifiedGutterWidth * 2 + Tokens.unifiedSignWidth + 16 + code
    }
}

#if DEBUG
private func previewDiff(_ path: String, staged: Bool) -> FileDiff {
    let file = Fixtures.files.first { $0.path == path }!
    return FixtureDiffs.diff(for: file, context: .workingTree(staged: staged))!
}

#Preview("Unified — light") {
    DiffView(diff: previewDiff("src/commands/sync.ts", staged: true), mode: .unified)
        .workbenchTheme(.standard)
        .frame(width: 760, height: 520)
}

#Preview("Split — light") {
    DiffView(diff: previewDiff("src/commands/sync.ts", staged: true), mode: .split)
        .workbenchTheme(.standard)
        .frame(width: 820, height: 520)
}

#Preview("Deleted — light") {
    DiffView(diff: previewDiff("src/legacy/poller.ts", staged: false), mode: .split)
        .workbenchTheme(.standard)
        .frame(width: 760, height: 320)
}

#Preview("Split — dark") {
    DiffView(diff: previewDiff("src/commands/sync.ts", staged: true), mode: .split)
        .workbenchTheme(.darkStandard)
        .frame(width: 820, height: 520)
        .preferredColorScheme(.dark)
}
#endif
