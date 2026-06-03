import SwiftUI
import AppKit

/// Renders a `FileDiff` unified or split, with deleted-file and binary special cases.
struct DiffView: View {
    @Environment(\.workbenchTheme) private var theme
    let diff: FileDiff
    let mode: DiffMode

    var body: some View {
        Group {
            if diff.isBinary {
                binary
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

    private var binary: some View {
        VStack(spacing: 6) {
            Image(systemName: IconLibrary.file).font(.system(size: 22)).foregroundStyle(theme.ink3)
            Text("Binary file").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink2)
            Text("+\(diff.file.additions) \u{2212}\(diff.file.deletions)")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
