# GitWorkbench Changes View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Build the Changes view — a grouped Staged/Changes file list, the commit composer, the diff pane (file header + `DiffView`), and the discard-confirm popover — and wire it into `GitWorkbenchView` for `activeView == .changes`.

**Architecture:** Plan 7 (Foundation→Chrome on `main`). `ChangesBody(store:)` is a two-pane view: a 320-wide pane (file list scroll + docked commit composer) and a fluid diff pane. It reads `store.state` and calls store intents (`toggleStage`/`stageAll`/`unstageAll`/`select(file:)`/`setCommitMessage`/`commit`/`requestDiscard`/`confirmDiscard`/`cancelDiscard`). Replaces the `.changes` placeholder in `GitWorkbenchView.body(for:)`. Internal views reading `@Environment(\.workbenchTheme)`.

**Tech Stack:** Swift 6, SwiftPM, macOS 15+, SwiftUI, XCTest. Zero deps.

**Conventions:** Metrics/colors from §03 (Changes view) + §04. Internal views. `\u{2026}`/`\u{2019}`/`\u{2212}` for non-ASCII. Run from repo root; execution on `feat/changes-view`. After merge, capture via the demo `--shot --view changes --select <path>`.

---

### Task 1: FileListRow + ChangesFileList

**Files:**
- Create: `Sources/GitWorkbench/Views/Changes/FileListRow.swift`
- Create: `Sources/GitWorkbench/Views/Changes/ChangesFileList.swift`

- [ ] **Step 1: Write `FileListRow.swift`**

```swift
import SwiftUI

/// One changed-file row: stage box · status glyph · name · dir · (stats | hover-discard).
struct FileListRow: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    @State private var hover = false
    let file: FileChange

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
        .padding(.horizontal, 12)
        .frame(height: Tokens.changesRowHeight)
        .frame(maxWidth: .infinity)
        .background(rowBackground(selected: selected))
        .contentShape(Rectangle())
        .onTapGesture { store.select(file: file.id) }
        .onHover { hover = $0 }
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
```

- [ ] **Step 2: Write `ChangesFileList.swift`**

```swift
import SwiftUI

/// The scrollable Staged / Changes groups (or a clean-tree empty state).
struct ChangesFileList: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    @State private var stagedCollapsed = false
    @State private var changesCollapsed = false

    var body: some View {
        let staged = store.state.staged
        let unstaged = store.state.unstaged
        if staged.isEmpty && unstaged.isEmpty {
            EmptyState(icon: IconLibrary.check, title: "Working tree clean",
                       subtitle: "No changes to commit.", iconColor: theme.statusAdded)
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if !staged.isEmpty {
                        group(title: "Staged", count: staged.count, collapsed: $stagedCollapsed,
                              actionTitle: "Unstage all", action: { Task { await store.unstageAll() } },
                              files: staged)
                    }
                    if !unstaged.isEmpty {
                        group(title: "Changes", count: unstaged.count, collapsed: $changesCollapsed,
                              actionTitle: "Stage all", action: { Task { await store.stageAll() } },
                              files: unstaged)
                    }
                }
            }
        }
    }

    private func group(title: String, count: Int, collapsed: Binding<Bool>,
                       actionTitle: String, action: @escaping () -> Void,
                       files: [FileChange]) -> some View {
        Section {
            if !collapsed.wrappedValue {
                ForEach(files) { FileListRow(store: store, file: $0) }
            }
        } header: {
            HStack(spacing: 6) {
                Button { collapsed.wrappedValue.toggle() } label: {
                    Image(systemName: collapsed.wrappedValue ? IconLibrary.chevronRight : IconLibrary.chevronDown)
                        .font(.system(size: 10)).foregroundStyle(theme.ink3)
                }.buttonStyle(.plain)
                Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(theme.ink3)
                Text("\(count)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.ink3)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.black.opacity(0.06), in: Capsule())
                Spacer()
                Button(actionTitle, action: action)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.accentDeep).buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(theme.sidebar)
        }
    }
}
```

- [ ] **Step 3: Build & commit**

Run: `swift build`
Expected: succeeds.

```bash
git add Sources/GitWorkbench/Views/Changes/FileListRow.swift Sources/GitWorkbench/Views/Changes/ChangesFileList.swift
git commit -m "Changes: add FileListRow and the Staged/Changes file list"
```

---

### Task 2: CommitComposer

**Files:**
- Create: `Sources/GitWorkbench/Views/Changes/CommitComposer.swift`

> Docked at the bottom of the file-list pane: a `TextEditor` message field + a `canCommit`-gated commit button. ⌘↵ commits.

- [ ] **Step 1: Write `CommitComposer.swift`**

```swift
import SwiftUI

struct CommitComposer: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        let canCommit = store.state.canCommit
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                if store.state.commitMessage.isEmpty {
                    Text("Message (\u{2318}\u{21A9} to commit)")
                        .font(.system(size: 13)).foregroundStyle(theme.ink3)
                        .padding(.horizontal, 12).padding(.vertical, 10).allowsHitTesting(false)
                }
                TextEditor(text: messageBinding)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .focused($focused)
            }
            .frame(height: 58)
            .background(theme.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? theme.accentRing : theme.sep, lineWidth: focused ? 1.5 : 1)
            )

            Button { Task { await store.commit() } } label: {
                HStack(spacing: 7) {
                    Image(systemName: IconLibrary.check)
                    Text(commitTitle)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canCommit ? .white : theme.ink3)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(canCommit ? theme.accent : Color.black.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12)
        .background(theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(theme.sep).frame(height: 1) }
    }

    private var commitTitle: String {
        let n = store.state.staged.count
        let files = n == 1 ? "file" : "files"
        return n > 0 ? "Commit \(n) \(files) to \(store.state.repo.currentBranch)" : "Commit"
    }
    private var messageBinding: Binding<String> {
        Binding(get: { store.state.commitMessage }, set: { store.setCommitMessage($0) })
    }
}
```

- [ ] **Step 2: Build & commit**

Run: `swift build`
Expected: succeeds.

```bash
git add Sources/GitWorkbench/Views/Changes/CommitComposer.swift
git commit -m "Changes: add CommitComposer (message field + commit button + cmd-return)"
```

---

### Task 3: Diff pane + discard confirm

**Files:**
- Create: `Sources/GitWorkbench/Views/Changes/ChangesDiffPane.swift`
- Create: `Sources/GitWorkbench/Views/Shared/ConfirmDiscardPopover.swift`

- [ ] **Step 1: Write `ChangesDiffPane.swift`**

```swift
import SwiftUI

/// The diff pane: a file header (meta + stage/discard actions) over the `DiffView`, or an empty state.
struct ChangesDiffPane: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if let file = selectedFile {
                header(file)
                if let diff = store.state.currentDiff, diff.file.id == file.id {
                    DiffView(diff: diff, mode: store.state.diffMode)
                } else {
                    Spacer()
                }
            } else {
                EmptyState(icon: IconLibrary.file,
                           title: store.state.repo.files.isEmpty ? "Nothing to show \u{2014} working tree is clean"
                                                                  : "Select a file to view changes")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.winBg)
    }

    private var selectedFile: FileChange? {
        store.state.repo.files.first { $0.id == store.state.selectedFileID }
    }

    private func header(_ file: FileChange) -> some View {
        HStack(spacing: 9) {
            StatusGlyph(status: file.status, size: 16)
            Text(file.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink).lineLimit(1)
            if !file.directory.isEmpty {
                Text("\(file.directory)/").font(.system(size: 11.5)).foregroundStyle(theme.ink3).lineLimit(1)
            }
            StatChips(additions: file.additions, deletions: file.deletions)
            Rectangle().fill(theme.sep).frame(width: 1, height: 14)
            Text(file.status.label).font(.system(size: 11.5)).foregroundStyle(theme.ink3)
            Spacer(minLength: 8)
            ToolButton(icon: file.isStaged ? IconLibrary.minus : IconLibrary.plus,
                       label: file.isStaged ? "Unstage" : "Stage") { Task { await store.toggleStage(file.id) } }
            ToolButton(icon: IconLibrary.discard, label: "Discard", role: .danger) { store.requestDiscard(file.id) }
        }
        .padding(.horizontal, 16)
        .frame(height: Tokens.diffHeaderHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }
}
```

- [ ] **Step 2: Write `ConfirmDiscardPopover.swift`**

```swift
import SwiftUI

/// A centered, scrimmed confirm card for the irreversible discard action.
struct ConfirmDiscardPopover: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    let file: FileChange

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
                .onTapGesture { store.cancelDiscard() }
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.delBg)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: IconLibrary.discard).font(.system(size: 18)).foregroundStyle(theme.delInk))
                Text("Discard changes in \(file.name)?")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(theme.ink)
                Text("This will permanently discard \(file.additions + file.deletions) line change(s). You can\u{2019}t undo this.")
                    .font(.system(size: 12.5)).foregroundStyle(theme.ink2).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    capsuleButton("Cancel", fill: Color.black.opacity(0.07), fg: theme.ink) { store.cancelDiscard() }
                    capsuleButton("Discard Changes", fill: theme.statusDeleted, fg: .white) { Task { await store.confirmDiscard() } }
                }
            }
            .padding(20).frame(width: 360)
            .background(theme.winBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: .black.opacity(0.30), radius: 25, y: 18)
        }
    }

    private func capsuleButton(_ title: String, fill: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(fg)
                .padding(.horizontal, 16).frame(height: 30)
                .background(fill, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Build & commit**

Run: `swift build`
Expected: succeeds.

```bash
git add Sources/GitWorkbench/Views/Changes/ChangesDiffPane.swift Sources/GitWorkbench/Views/Shared/ConfirmDiscardPopover.swift
git commit -m "Changes: add diff pane (header + DiffView) and discard confirm popover"
```

---

### Task 4: ChangesBody + wire into GitWorkbenchView

**Files:**
- Create: `Sources/GitWorkbench/Views/Changes/ChangesBody.swift`
- Modify: `Sources/GitWorkbench/GitWorkbenchView.swift` (use `ChangesBody` for `.changes`)

- [ ] **Step 1: Write `ChangesBody.swift`**

```swift
import SwiftUI

/// The Changes workspace: file-list + composer pane (320), then the diff pane; discard confirm overlays.
struct ChangesBody: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ChangesFileList(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                CommitComposer(store: store)
            }
            .frame(width: Tokens.changesListWidth)
            .background(theme.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(theme.sep).frame(width: 1) }

            ChangesDiffPane(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay { if let file = store.state.pendingDiscard { ConfirmDiscardPopover(store: store, file: file) } }
    }
}
```

- [ ] **Step 2: Wire it into `GitWorkbenchView.swift`**

In `Sources/GitWorkbench/GitWorkbenchView.swift`, change the `.changes` case of `body(for:)` from the placeholder to:

```swift
        case .changes: ChangesBody(store: store)
```

(Leave `.history` / `.stashes` as their placeholders for now.)

- [ ] **Step 3: Build & run the full suite**

Run: `swift build && swift test`
Expected: build succeeds (previews compile); all tests pass (~67).

- [ ] **Step 4: Verify in the demo**

Run:
```bash
swift build
.build/debug/GitWorkbenchDemo --shot /tmp/changes.png --view changes --select src/commands/sync.ts >/tmp/d.log 2>&1 &
sleep 7; pkill -f GitWorkbenchDemo
```
Open `/tmp/changes.png`. Confirm: the Staged group (sync.ts/index.ts/logger.ts) + Changes group with stage boxes, status glyphs, names, dirs, stats; a selected file (accent) showing its diff in the right pane with the file header (Stage/Unstage + Discard); the commit composer at the bottom with the enabled "Commit 3 files to feat/auto-sync" button.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Views/Changes/ChangesBody.swift Sources/GitWorkbench/GitWorkbenchView.swift
git commit -m "Changes: compose ChangesBody and wire it into GitWorkbenchView"
```

---

## Self-Review

**1. Spec coverage (vs. §03 Changes view):**
- File list: Staged/Changes groups (collapsible, sticky headers, count badge, bulk Stage-all/Unstage-all), `FileListRow` (stage box → toggleStage, status glyph, name, dir, stats/hover-discard, selection), clean-tree empty state → Tasks 1 ✓
- Commit composer (TextEditor + placeholder + focus ring, canCommit-gated button with file count + branch, ⌘↵) → Task 2 ✓
- Diff pane (file header: meta + status word + Stage/Unstage + Discard; `DiffView`; no-selection empty state) → Task 3 ✓
- Confirm discard popover (scrim, card, Cancel/Discard) → Task 3 ✓
- ChangesBody composition + wired into `GitWorkbenchView` → Task 4 ✓
- **Deferred:** keyboard ↑/↓ selection, context menus, ⌘⌫ discard shortcut → a11y/polish plan. Selected-row stat color rendered white inline (a small, intentional readability choice since `StatChips` is fixed green/red).

**2. Placeholder scan:** Complete code in every step; the demo `--shot` check in Task 4 is a real visual verification (not manual-only). `.history`/`.stashes` remain labeled placeholders (Plan 8).

**3. Type/signature consistency:** All views take `@ObservedObject store`. Store intents `toggleStage`/`stageAll`/`unstageAll`/`select(file:)`/`requestDiscard`/`confirmDiscard`/`cancelDiscard`/`setCommitMessage`/`commit` (Plan 3) used correctly. `StageBox`/`StatusGlyph`/`StatChips`/`ToolButton`/`EmptyState` (Plan 4), `DiffView(diff:mode:)` (Plan 5), `Tokens.changesListWidth/changesRowHeight/diffHeaderHeight`, `theme.*`, `IconLibrary.*`, `\.workbenchTheme` used consistently. `ChangesBody(store:)` slots into `GitWorkbenchView.body(for:)`.
