# GitWorkbench Diff Renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `DiffView` — the unified + split diff renderer — including the tested split-derivation logic (`DiffSplitter`), the hunk-header band, the unified and split row renderers, and the deleted-file / binary modes.

**Architecture:** Plan 5 of the program (Foundation + Provider + Store + Primitives on `main`). `DiffView(diff:mode:)` takes a `FileDiff` (the store's `currentDiff`) and a `DiffMode`, and renders it monospaced. The split layout is derived from unified hunks by `DiffSplitter` (a direct port of `splitRows` in `reference/src/diff.jsx`). Views are **internal**, read `@Environment(\.workbenchTheme)`, and use the Plan 1 `Tokens` diff metrics. Verified by `swift build` + the split-logic unit tests + a manual canvas/snapshot check.

**Tech Stack:** Swift 6, SwiftPM, macOS 15+, SwiftUI, XCTest. No third-party dependencies.

**Conventions:** Exact metrics/colors from `reference/src/diff.jsx` and §04. Minus sign is `\u{2212}`. TDD for `DiffSplitter`; build-verify the views. Run from repo root; execution on a fresh `feat/diff-renderer` branch.

---

### Task 1: DiffSplitter (split derivation) + tests

**Files:**
- Create: `Sources/GitWorkbench/Views/Diff/DiffSplitter.swift`
- Test: `Tests/GitWorkbenchTests/DiffSplitterTests.swift`

> Port of `splitRows` in `diff.jsx`: accumulate runs of deletions (left) and additions (right); on each context line, flush the run by zipping del↔add into rows (padding the shorter side with `nil`), then emit the context line on both sides.

- [ ] **Step 1: Write the failing test**

`Tests/GitWorkbenchTests/DiffSplitterTests.swift`:

```swift
import XCTest
@testable import GitWorkbench

final class DiffSplitterTests: XCTestCase {
    private func line(_ kind: DiffLine.Kind, o: Int?, n: Int?, _ text: String) -> DiffLine {
        DiffLine(kind: kind, oldNumber: o, newNumber: n, text: text)
    }

    func test_pureAdditions_leftEmptyRightAdds() {
        let rows = DiffSplitter.rows([
            line(.addition, o: nil, n: 1, "a"),
            line(.addition, o: nil, n: 2, "b"),
        ])
        XCTAssertEqual(rows.count, 2)
        XCTAssertNil(rows[0].left); XCTAssertEqual(rows[0].right?.text, "a")
        XCTAssertNil(rows[1].left); XCTAssertEqual(rows[1].right?.text, "b")
    }

    func test_pureDeletions_rightEmptyLeftDels() {
        let rows = DiffSplitter.rows([
            line(.deletion, o: 1, n: nil, "x"),
            line(.deletion, o: 2, n: nil, "y"),
        ])
        XCTAssertEqual(rows.map { $0.left?.text }, ["x", "y"])
        XCTAssertEqual(rows.map { $0.right?.text }, [nil, nil])
    }

    func test_interleaved_zipsAndPads() {
        // ctx, del, del, add, ctx  →  ctx/ctx, (d1|a1), (d2|·), ctx/ctx
        let rows = DiffSplitter.rows([
            line(.context, o: 1, n: 1, "c1"),
            line(.deletion, o: 2, n: nil, "d1"),
            line(.deletion, o: 3, n: nil, "d2"),
            line(.addition, o: nil, n: 2, "a1"),
            line(.context, o: 4, n: 3, "c2"),
        ])
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].left?.text, "c1"); XCTAssertEqual(rows[0].right?.text, "c1")
        XCTAssertEqual(rows[1].left?.text, "d1"); XCTAssertEqual(rows[1].right?.text, "a1")
        XCTAssertEqual(rows[2].left?.text, "d2"); XCTAssertNil(rows[2].right)
        XCTAssertEqual(rows[3].left?.text, "c2"); XCTAssertEqual(rows[3].right?.text, "c2")
    }

    func test_context_showsOldOnLeftNewOnRight() {
        let rows = DiffSplitter.rows([line(.context, o: 5, n: 7, "ctx")])
        XCTAssertEqual(rows[0].left?.oldNumber, 5)
        XCTAssertEqual(rows[0].right?.newNumber, 7)
    }

    func test_rowIDsAreStableAcrossCalls() {
        let lines = [line(.deletion, o: 1, n: nil, "x"), line(.addition, o: nil, n: 1, "y")]
        XCTAssertEqual(DiffSplitter.rows(lines).map(\.id), DiffSplitter.rows(lines).map(\.id))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DiffSplitterTests`
Expected: FAIL — `DiffSplitter` undefined.

- [ ] **Step 3: Write the implementation**

`Sources/GitWorkbench/Views/Diff/DiffSplitter.swift`:

```swift
import Foundation

/// One row of a split diff: a left (old) cell and a right (new) cell, either of which
/// may be `nil` (a missing counterpart). For context lines both sides hold the same line.
struct SplitRow: Identifiable {
    let id: Int
    var left: DiffLine?
    var right: DiffLine?
}

/// Derives split rows from a hunk's unified lines. Port of `splitRows` in reference/src/diff.jsx.
enum DiffSplitter {
    static func rows(_ lines: [DiffLine]) -> [SplitRow] {
        var rows: [SplitRow] = []
        var dels: [DiffLine] = []
        var adds: [DiffLine] = []

        func flush() {
            let count = max(dels.count, adds.count)
            for i in 0..<count {
                rows.append(SplitRow(id: rows.count,
                                     left: i < dels.count ? dels[i] : nil,
                                     right: i < adds.count ? adds[i] : nil))
            }
            dels.removeAll(keepingCapacity: true)
            adds.removeAll(keepingCapacity: true)
        }

        for line in lines {
            switch line.kind {
            case .context:
                flush()
                rows.append(SplitRow(id: rows.count, left: line, right: line))
            case .deletion:
                dels.append(line)
            case .addition:
                adds.append(line)
            }
        }
        flush()
        return rows
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DiffSplitterTests`
Expected: PASS (all five).

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Views/Diff/DiffSplitter.swift Tests/GitWorkbenchTests/DiffSplitterTests.swift
git commit -m "Diff: add DiffSplitter (split derivation) with tests"
```

---

### Task 2: Hunk header + unified row

**Files:**
- Create: `Sources/GitWorkbench/Views/Diff/UnifiedDiff.swift`

> The `@@` header band and a single unified diff row. Metrics from `diff.jsx`: mono 12pt / line-height 20; two 46pt number gutters (right-aligned, 12pt trailing inset, tertiary); a 20pt centered bold sign column (`+` addInk / `−` delInk / space); flexible code (no-wrap, 16pt trailing, label ink). Row background add/del tint; a 3px leading edge bar on changed rows.

- [ ] **Step 1: Write `UnifiedDiff.swift`**

```swift
import SwiftUI

/// The `@@ … @@` hunk header band.
struct HunkHeaderBand: View {
    @Environment(\.workbenchTheme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(theme.ink3)
            .lineLimit(1)
            .padding(.vertical, 5)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.hunkHeaderBg)
            .overlay(alignment: .top) { Rectangle().fill(theme.sep).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }
}

/// One unified diff line: [oldNo][newNo][sign][code], tinted by kind.
struct UnifiedDiffRow: View {
    @Environment(\.workbenchTheme) private var theme
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            gutter(line.oldNumber)
            gutter(line.newNumber)
            Text(sign)
                .frame(width: Tokens.unifiedSignWidth)
                .foregroundStyle(signColor)
                .fontWeight(.bold)
            Text(line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 16)
                .foregroundStyle(theme.ink)
        }
        .font(.system(size: 12, design: .monospaced))
        .lineLimit(1)
        .frame(minHeight: Tokens.diffLineHeight)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(edgeBar).frame(width: Tokens.diffEdgeBarWidth)
        }
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .foregroundStyle(theme.ink3)
            .padding(.trailing, 12)
            .frame(width: Tokens.unifiedGutterWidth, alignment: .trailing)
    }

    private var sign: String {
        switch line.kind { case .addition: "+"; case .deletion: "\u{2212}"; case .context: " " }
    }
    private var signColor: Color {
        switch line.kind { case .addition: theme.addInk; case .deletion: theme.delInk; case .context: theme.ink3 }
    }
    private var rowBackground: Color {
        switch line.kind { case .addition: theme.addBg; case .deletion: theme.delBg; case .context: .clear }
    }
    private var edgeBar: Color {
        switch line.kind { case .addition: theme.addGut; case .deletion: theme.delGut; case .context: .clear }
    }
}
```

- [ ] **Step 2: Build & commit**

Run: `swift build`
Expected: succeeds.

```bash
git add Sources/GitWorkbench/Views/Diff/UnifiedDiff.swift
git commit -m "Diff: add HunkHeaderBand and UnifiedDiffRow"
```

---

### Task 3: Split row

**Files:**
- Create: `Sources/GitWorkbench/Views/Diff/SplitDiff.swift`

> Two side-by-side cells per split row. Metrics from `diff.jsx`: each side has a 40pt right-aligned number gutter (10pt trailing, tertiary), a 14pt centered bold sign (only on changed cells), and truncating code; a missing-counterpart cell uses the empty tint with transparent text; a 1px divider runs after the left side.

- [ ] **Step 1: Write `SplitDiff.swift`**

```swift
import SwiftUI

/// One side (left = old, right = new) of a split diff row.
struct SplitSide: View {
    enum Side { case left, right }
    @Environment(\.workbenchTheme) private var theme
    let cell: DiffLine?
    let side: Side

    var body: some View {
        HStack(spacing: 0) {
            Text(number)
                .foregroundStyle(theme.ink3)
                .padding(.trailing, 10)
                .frame(width: Tokens.splitGutterWidth, alignment: .trailing)
            Text(sign)
                .frame(width: Tokens.splitSignWidth)
                .foregroundStyle(signColor)
                .fontWeight(.bold)
            Text(cellText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 10)
                .foregroundStyle(cell == nil ? .clear : theme.ink)
        }
        .frame(minHeight: Tokens.diffLineHeight)
        .background(background)
        .overlay(alignment: .trailing) {
            if side == .left { Rectangle().fill(theme.sep).frame(width: 1) }
        }
    }

    private var number: String {
        guard let cell else { return "" }
        let n = side == .left ? cell.oldNumber : cell.newNumber
        return n.map(String.init) ?? ""
    }
    private var isChange: Bool { cell != nil && cell!.kind != .context }
    private var sign: String { isChange ? (cell!.kind == .addition ? "+" : "\u{2212}") : "" }
    private var signColor: Color { cell?.kind == .addition ? theme.addInk : theme.delInk }
    private var cellText: String {
        guard let cell else { return "" }
        return cell.text.isEmpty ? " " : cell.text
    }
    private var background: Color {
        guard let cell else { return theme.splitEmptyCell }
        switch cell.kind { case .addition: return theme.addBg; case .deletion: return theme.delBg; case .context: return .clear }
    }
}

/// One split row: left side + right side.
struct SplitDiffRow: View {
    let row: SplitRow
    var body: some View {
        HStack(spacing: 0) {
            SplitSide(cell: row.left, side: .left)
            SplitSide(cell: row.right, side: .right)
        }
        .font(.system(size: 12, design: .monospaced))
    }
}
```

- [ ] **Step 2: Build & commit**

Run: `swift build`
Expected: succeeds.

```bash
git add Sources/GitWorkbench/Views/Diff/SplitDiff.swift
git commit -m "Diff: add SplitSide and SplitDiffRow"
```

---

### Task 4: DiffView container

**Files:**
- Create: `Sources/GitWorkbench/Views/Diff/DiffView.swift`

> Switches unified/split, lazily renders hunks, and special-cases the deleted-file mode (all lines, no headers, 0.92 opacity — per `diff.jsx`) and binary mode (a metadata row). Uses `LazyVStack` (a "Load more" threshold for very large diffs is a future refinement, noted).

- [ ] **Step 1: Write `DiffView.swift`**

```swift
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
                ScrollView([.vertical, .horizontal]) { content }
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
        ScrollView([.vertical, .horizontal]) {
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
```

- [ ] **Step 2: Build & run the full suite**

Run: `swift build && swift test`
Expected: build succeeds (previews compile); all tests pass (incl. DiffSplitterTests).

- [ ] **Step 3: Verify diffs render**

Open `Package.swift` in Xcode and resume the canvas for `DiffView.swift`. Confirm: unified shows two gutters + sign + tinted add/del rows with edge bars; split shows paired cells with the empty tint on missing counterparts and the center divider; deleted shows the dimmed all-removed block; light + dark both correct. Compare against `reference/Git Workbench Prototype.html` (toggle unified/split).

- [ ] **Step 4: Commit**

```bash
git add Sources/GitWorkbench/Views/Diff/DiffView.swift
git commit -m "Diff: add DiffView container (unified/split/deleted/binary)"
```

---

## Self-Review

**1. Spec coverage (vs. §03 Diff + §02 split derivation + `diff.jsx`):**
- Split derivation (port of `splitRows`) + `SplitRow` → Task 1 ✓ (TDD: pure-add, pure-delete, interleaved-with-padding, context both sides, stable ids).
- Hunk header band + unified row (gutters/sign/code, tint, 3px edge bar) → Task 2 ✓.
- Split side + row (40/14 gutters, empty tint, divider, truncation) → Task 3 ✓.
- DiffView container: unified/split switch, deleted-file (no headers, 0.92 opacity), binary, lazy hunks → Task 4 ✓.
- **Deferred:** the "Load more" threshold for very large diffs (LazyVStack suffices for the fixtures; noted). Syntax highlighting is out of scope (handoff optional).

**2. Placeholder scan:** Complete code in every step; the only manual step is the Task 4 canvas check (the snapshot tool will also capture these). `\u{2212}` used for the minus sign.

**3. Type/signature consistency:** `DiffSplitter.rows(_:)`/`SplitRow(id:left:right:)` (Task 1) used by `SplitDiffRow`/`DiffView` (Tasks 3–4). `DiffLine`/`DiffHunk`/`FileDiff` (Plan 1, Identifiable) drive the `ForEach`es. `Tokens.unifiedGutterWidth/unifiedSignWidth/splitGutterWidth/splitSignWidth/diffEdgeBarWidth/diffLineHeight`, `theme.addBg/delBg/addGut/delGut/addInk/delInk/ink/ink3/sep/hunkHeaderBg/splitEmptyCell/winBg`, `\.workbenchTheme`, `Fixtures.files`, `FixtureDiffs.diff(for:context:)`, `IconLibrary.file` — all from Plans 1–4, used consistently. `DiffView(diff:mode:)` is the consumer the Changes/History/Stash view plans will embed.
