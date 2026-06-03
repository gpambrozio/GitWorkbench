# GitWorkbench History + Stash Views Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Build the History view (commit-graph list + commit detail) and the Stash view (stash list + stash detail with Apply/Pop/Drop), sharing a `DetailFileRow`/changed-files block and ref/author helpers, and wire both into `GitWorkbenchView`.

**Architecture:** Plan 8 (Foundation→ChangesView on `main`). Both views are list+detail: a 360-wide list pane + a fluid detail pane (metadata → changed-files → `DiffView`). They reuse the diff `id`-guard from the Changes pane (`currentDiff` is one shared slot). Adds three store intents: `selectCommitFile`, `selectStashFile`, `showToast`. Internal views reading `@Environment(\.workbenchTheme)`.

**Tech Stack:** Swift 6, SwiftPM, macOS 15+, SwiftUI, XCTest. Zero deps.

**Conventions:** Metrics/colors from §03 (History/Stash) + §04. Internal views. `\u{00B7}` (·), `\u{2026}`. Run from repo root; execution on `feat/history-stash`. Verify via demo `--shot --view history` / `--view stashes`.

---

### Task 1: Store intents + shared detail components

**Files:**
- Modify: `Sources/GitWorkbench/Store/GitWorkbenchStore.swift` (append intents)
- Create: `Sources/GitWorkbench/Views/Shared/AuthorHue.swift`
- Create: `Sources/GitWorkbench/Views/Shared/RefPill.swift`
- Create: `Sources/GitWorkbench/Views/Shared/DetailFiles.swift`

- [ ] **Step 1: Append store intents** (same-file extension in `GitWorkbenchStore.swift`):

```swift
// MARK: - Detail-pane intents

extension GitWorkbenchStore {
    public func selectCommitFile(_ fileID: FileChange.ID) {
        state.selectedCommitFileID = fileID
        guard let commitID = state.selectedCommitID,
              let file = state.commits.first(where: { $0.id == commitID })?.files.first(where: { $0.id == fileID })
        else { return }
        diffTask?.cancel()
        diffTask = Task { [weak self] in await self?.loadDiff(for: file, context: .commit(commitID)) }
    }

    public func selectStashFile(_ fileID: FileChange.ID) {
        state.selectedStashFileID = fileID
        guard let stashID = state.selectedStashID,
              let file = state.stashes.first(where: { $0.id == stashID })?.files.first(where: { $0.id == fileID })
        else { return }
        diffTask?.cancel()
        diffTask = Task { [weak self] in await self?.loadDiff(for: file, context: .stash(stashID)) }
    }

    public func showToast(_ message: String, style: Toast.Style = .success) {
        state.toast = Toast(message: message, style: style)
    }
}
```

- [ ] **Step 2: Write `AuthorHue.swift`**

```swift
import Foundation

/// Maps author initials to an OKLCH hue. Fixture authors are pinned to the prototype's hues;
/// others derive a stable hue from their initials.
func authorHue(_ initials: String) -> Double {
    switch initials {
    case "GA": return 295
    case "MP": return 25
    default:
        let sum = initials.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 360)
    }
}
```

- [ ] **Step 3: Write `RefPill.swift`**

```swift
import SwiftUI

/// A HEAD / branch / tag pill shown on a commit row.
struct RefPill: View {
    @Environment(\.workbenchTheme) private var theme
    let ref: CommitRef
    var selected: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let icon = IconLibrary.symbol(for: ref) { Image(systemName: icon).font(.system(size: 8)) }
            Text(label)
        }
        .font(.system(size: 9.5, weight: .bold))
        .padding(.horizontal, 5).padding(.vertical, 1)
        .foregroundStyle(selected ? .white : foreground)
        .background(selected ? Color.white.opacity(0.22) : background,
                    in: RoundedRectangle(cornerRadius: Tokens.pillRadius, style: .continuous))
    }

    private var label: String {
        switch ref { case .head: "HEAD"; case .branch(let n): n; case .tag(let t): t }
    }
    private var foreground: Color {
        switch ref { case .head: theme.accentDeep; case .branch: theme.statusRenamed; case .tag: theme.statusAdded }
    }
    private var background: Color {
        switch ref {
        case .head: theme.accentSoft
        case .branch: theme.statusRenamed.opacity(0.13)
        case .tag: theme.statusAdded.opacity(0.13)
        }
    }
}
```

- [ ] **Step 4: Write `DetailFiles.swift`** (shared changed-files block for History + Stash detail)

```swift
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
```

- [ ] **Step 5: Build & commit**

Run: `swift build && swift test`
Expected: succeeds; ~67 tests pass.

```bash
git add Sources/GitWorkbench/Store/GitWorkbenchStore.swift Sources/GitWorkbench/Views/Shared/AuthorHue.swift Sources/GitWorkbench/Views/Shared/RefPill.swift Sources/GitWorkbench/Views/Shared/DetailFiles.swift
git commit -m "History/Stash: add detail-pane store intents and shared RefPill/DetailFiles/AuthorHue"
```

---

### Task 2: History view

**Files:**
- Create: `Sources/GitWorkbench/Views/History/CommitGraphRow.swift`
- Create: `Sources/GitWorkbench/Views/History/CommitDetail.swift`
- Create: `Sources/GitWorkbench/Views/History/HistoryBody.swift`

- [ ] **Step 1: Write `CommitGraphRow.swift`**

```swift
import SwiftUI

/// A commit list row: graph column (line + node) + summary/refs + author/relative/sha.
struct CommitGraphRow: View {
    @ObservedObject var store: GitWorkbenchStore
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
    }
}
```

- [ ] **Step 2: Write `CommitDetail.swift`**

```swift
import SwiftUI
import AppKit

/// The commit detail pane: metadata (summary/body/author + copy-SHA) → changed files → diff.
struct CommitDetail: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    let commit: Commit

    var body: some View {
        VStack(spacing: 0) {
            metadata
            DetailFilesBlock(files: commit.files, selectedID: store.state.selectedCommitFileID) {
                store.selectCommitFile($0)
            }
            DetailDiffArea(store: store, selectedFileID: store.state.selectedCommitFileID)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(commit.summary).font(.system(size: 16, weight: .bold)).tracking(-0.2)
                .foregroundStyle(theme.ink).frame(maxWidth: .infinity, alignment: .leading)
            if !commit.body.isEmpty {
                Text(commit.body).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(theme.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8).textSelection(.enabled)
            }
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
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }
            .padding(.top, 14)
        }
        .padding(.init(top: 16, leading: 20, bottom: 14, trailing: 20))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }

    private func copySHA() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commit.shortSHA, forType: .string)
        store.showToast("Copied \(commit.shortSHA) to clipboard")
    }
}
```

- [ ] **Step 3: Write `HistoryBody.swift`**

```swift
import SwiftUI

/// The History workspace: commit list (360) + commit detail.
struct HistoryBody: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: IconLibrary.history).font(.system(size: 12)).foregroundStyle(theme.ink3)
                    Text("HISTORY").font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(theme.ink3)
                    Text("\(store.state.commits.count)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(theme.ink3).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.black.opacity(0.06), in: Capsule())
                    Spacer()
                    BranchPill(name: store.state.repo.currentBranch, dim: true, showsChevron: false, height: 24)
                }
                .padding(.horizontal, 14).frame(height: 44)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.state.commits) { CommitGraphRow(store: store, commit: $0) }
                    }
                }
            }
            .frame(width: Tokens.historyListWidth)
            .background(theme.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(theme.sep).frame(width: 1) }

            Group {
                if let commit = store.state.commits.first(where: { $0.id == store.state.selectedCommitID }) {
                    CommitDetail(store: store, commit: commit)
                } else {
                    EmptyState(icon: IconLibrary.history, title: "Select a commit",
                               subtitle: "Choose a commit to see its details.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.winBg)
        }
    }
}
```

- [ ] **Step 4: Build & commit**

Run: `swift build`
Expected: succeeds.

```bash
git add Sources/GitWorkbench/Views/History/CommitGraphRow.swift Sources/GitWorkbench/Views/History/CommitDetail.swift Sources/GitWorkbench/Views/History/HistoryBody.swift
git commit -m "History: add CommitGraphRow, CommitDetail, and HistoryBody"
```

---

### Task 3: Stash view

**Files:**
- Create: `Sources/GitWorkbench/Views/Stash/StashRow.swift`
- Create: `Sources/GitWorkbench/Views/Stash/StashDetail.swift`
- Create: `Sources/GitWorkbench/Views/Stash/StashBody.swift`

- [ ] **Step 1: Write `StashRow.swift`**

```swift
import SwiftUI

/// A stash list row: ref pill + message, then branch · relative · file count.
struct StashRow: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    @State private var hover = false
    let stash: Stash

    var body: some View {
        let selected = store.state.selectedStashID == stash.id
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(stash.ref)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? .white : theme.accentDeep)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(selected ? Color.white.opacity(0.22) : theme.accentSoft,
                                in: RoundedRectangle(cornerRadius: Tokens.pillRadius))
                Text(stash.message).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(selected ? .white : theme.ink).lineLimit(1)
            }
            HStack(spacing: 5) {
                Image(systemName: IconLibrary.branch).font(.system(size: 10))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : theme.ink3)
                Text(stash.branch).font(.system(size: 11))
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : theme.ink2)
                Text("\u{00B7} \(stash.relativeDate)").font(.system(size: 11))
                    .foregroundStyle(selected ? Color.white.opacity(0.7) : theme.ink3)
                Spacer(minLength: 6)
                Text("\(stash.files.count) file\(stash.files.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(selected ? Color.white.opacity(0.7) : theme.ink3)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? theme.accent : (hover ? Color.black.opacity(0.04) : .clear))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { Task { await store.selectStash(stash.id) } }
        .onHover { hover = $0 }
    }
}
```

- [ ] **Step 2: Write `StashDetail.swift`**

```swift
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
```

- [ ] **Step 3: Write `StashBody.swift`**

```swift
import SwiftUI

/// The Stash workspace: stash list (360) + stash detail (or empty states).
struct StashBody: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: IconLibrary.folder).font(.system(size: 12)).foregroundStyle(theme.ink3)
                    Text("STASHES").font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(theme.ink3)
                    Text("\(store.state.stashes.count)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(theme.ink3).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.black.opacity(0.06), in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 14).frame(height: 44)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }

                if store.state.stashes.isEmpty {
                    EmptyState(icon: IconLibrary.folder, title: "No stashes",
                               subtitle: "Shelved changes show up here.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.state.stashes) { StashRow(store: store, stash: $0) }
                        }
                    }
                }
            }
            .frame(width: Tokens.historyListWidth)
            .background(theme.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(theme.sep).frame(width: 1) }

            Group {
                if let stash = store.state.stashes.first(where: { $0.id == store.state.selectedStashID }) {
                    StashDetail(store: store, stash: stash)
                } else {
                    EmptyState(icon: IconLibrary.folder, title: "Select a stash",
                               subtitle: "Choose a stash to see its changes.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.winBg)
        }
    }
}
```

- [ ] **Step 4: Build & commit**

Run: `swift build`
Expected: succeeds.

```bash
git add Sources/GitWorkbench/Views/Stash/StashRow.swift Sources/GitWorkbench/Views/Stash/StashDetail.swift Sources/GitWorkbench/Views/Stash/StashBody.swift
git commit -m "Stash: add StashRow, StashDetail, and StashBody"
```

---

### Task 4: Wire both into GitWorkbenchView

**Files:**
- Modify: `Sources/GitWorkbench/GitWorkbenchView.swift`

- [ ] **Step 1: Replace the `.history`/`.stashes` placeholder cases**

In `GitWorkbenchView.body(for:)`, change:

```swift
        case .history: placeholder(IconLibrary.history, "History")
        case .stashes: placeholder(IconLibrary.folder, "Stashes")
```

to:

```swift
        case .history: HistoryBody(store: store)
        case .stashes: StashBody(store: store)
```

Then DELETE the now-unused `placeholder(_:_:)` helper function.

- [ ] **Step 2: Build & run the full suite**

Run: `swift build && swift test`
Expected: build succeeds (no unused-function warning); all tests pass (~67).

- [ ] **Step 3: Verify in the demo**

Run:
```bash
swift build
.build/debug/GitWorkbenchDemo --shot /tmp/history.png --view history >/tmp/d1.log 2>&1 & sleep 7; pkill -f GitWorkbenchDemo
.build/debug/GitWorkbenchDemo --shot /tmp/stash.png --view stashes >/tmp/d2.log 2>&1 & sleep 7; pkill -f GitWorkbenchDemo
```
Confirm `/tmp/history.png` (commit list + graph + selected commit's detail/diff) and `/tmp/stash.png` (stash list + selected stash's Apply/Pop/Drop + diff) are written.

- [ ] **Step 4: Commit**

```bash
git add Sources/GitWorkbench/GitWorkbenchView.swift
git commit -m "Views: wire HistoryBody and StashBody into GitWorkbenchView"
```

---

## Self-Review

**1. Spec coverage (vs. §03 History + Stash):**
- History: commit list header (HISTORY + count + read-only BranchPill); `CommitGraphRow` (graph line + node, summary + ref pills, avatar + author + relative + sha, selection); `CommitDetail` (summary/body/author + copy-SHA toast, changed files, diff) → Tasks 2 ✓
- Stash: stash list header; `StashRow` (ref pill + message, branch/relative/count, selection); `StashDetail` (ref/message + Apply/Pop/Drop, changed files, diff); empty state → Task 3 ✓
- Shared `DetailFileRow`/`DetailFilesBlock`/`DetailDiffArea` (with the `id`-guard), `RefPill`, `authorHue` → Task 1 ✓
- Store intents `selectCommitFile`/`selectStashFile`/`showToast` → Task 1 ✓
- Wire-in (remove placeholders) → Task 4 ✓
- **Deferred:** the "Stash" / "New branch" create buttons (no-op affordances), context menus, keyboard nav → a11y/polish plan. The `#FAFAFB` changed-files surface uses `theme.sidebar` (adapts to dark mode) instead of the literal hex.

**2. Placeholder scan:** Complete code in every step; the demo `--shot` checks in Task 4 are real visual verification. No `TODO`s.

**3. Type/signature consistency:** All views take `@ObservedObject store`. New intents `selectCommitFile`/`selectStashFile`/`showToast` (Task 1) used by `CommitDetail`/`StashDetail`. `selectCommit`/`selectStash`/`applyStash`/`popStash`/`dropStash` (Plan 3) drive selection + actions. `Avatar`/`StatusGlyph`/`StatChips`/`ToolButton`/`BranchPill`/`EmptyState` (Plan 4), `DiffView` (Plan 5), `Tokens.historyListWidth/detailFileRowHeight/pillRadius`, `theme.*`, `IconLibrary.*`, `\.workbenchTheme` used consistently. `HistoryBody`/`StashBody` slot into `GitWorkbenchView.body(for:)`. The `DetailDiffArea` `id`-guard mirrors the Changes pane (per the Plan 7 review note).
