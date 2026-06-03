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
                scrollingCode(minWidth: contentMinWidth(split: false)) { deletedRows }
            } else {
                // `.id(mode)` rebuilds the diff on a mode switch — the LazyVStack won't reliably swap
                // split rows for unified rows in place (it leaves a corrupted split/unified mix).
                scrollingCode(minWidth: contentMinWidth(split: mode == .split)) { content }
                    .id(mode)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.winBg)
    }

    /// Vertical + horizontal scroll. The content is at least as wide as the longest line (so long
    /// lines scroll instead of truncating) and at least the pane width (so short diffs still fill it).
    private func scrollingCode<V: View>(minWidth: CGFloat, @ViewBuilder _ inner: () -> V) -> some View {
        let inner = inner()
        return GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                // A concrete width (not minWidth) — inside a horizontal ScrollView the proposed width
                // is unbounded, so minWidth has nothing to floor against and the content collapses.
                inner.frame(width: max(minWidth, geo.size.width), alignment: .topLeading)
            }
        }
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(diff.hunks) { hunk in
                HunkHeaderBand(text: hunk.header)
                if mode == .split {
                    ForEach(DiffSplitter.rows(hunk.lines)) { SplitDiffRow(row: $0) }
                } else {
                    ForEach(hunk.lines) { UnifiedDiffRow(line: $0) }
                }
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

    private var monoFont: NSFont { .monospacedSystemFont(ofSize: 12, weight: .regular) }

    /// Width of the longest code line (measured once on the longest-by-character line).
    private var maxCodeWidth: CGFloat {
        guard let longest = diff.hunks.flatMap(\.lines).map(\.text).max(by: { $0.count < $1.count }) else { return 0 }
        return (longest as NSString).size(withAttributes: [.font: monoFont]).width
    }

    /// Total content width = fixed gutters/signs for the mode + the code column (+ a clip-safety buffer).
    private func contentMinWidth(split: Bool) -> CGFloat {
        let code = maxCodeWidth + 28
        // unified: 2 gutters (46) + sign (20) + trailing (16). split: per side gutter (40) + sign (14) + trailing (10), ×2 + divider.
        return split ? 2 * (Tokens.splitGutterWidth + Tokens.splitSignWidth + 10 + code) + 1
                     : Tokens.unifiedGutterWidth * 2 + Tokens.unifiedSignWidth + 16 + code
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
