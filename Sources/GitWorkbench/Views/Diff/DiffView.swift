import SwiftUI

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
                deleted
            } else {
                ScrollView(.vertical) { content }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.winBg)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Deleted file: all lines as unified rows, no headers, dimmed (diff.jsx).
    private var deleted: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(diff.hunks) { hunk in
                    ForEach(hunk.lines) { UnifiedDiffRow(line: $0) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(0.92)
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
