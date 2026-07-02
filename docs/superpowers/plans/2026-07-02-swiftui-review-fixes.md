# SwiftUI Review Fixes (19 approved findings) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the 19 approved findings from the 2026-07-02 SwiftUI expert review: granular `@Observable` state, hot-path fixes, one list-identity fix, accessibility/keyboard semantics, and polish.

**Architecture:** The core change (A1) dissolves the store's single `state` property into per-field `@Observable` stored properties while keeping a computed `WorkbenchState` snapshot (`store.state`) so tests, demos, and hosts keep compiling — views then migrate to the granular properties. Everything else layers on top: `ColumnLayout` goes `@Observable`, hot computations move out of `body`, rows narrow their dependencies, and gesture-only controls gain button/checkbox semantics.

**Tech Stack:** Swift 6 (language mode v6), SwiftUI, macOS 15+, XCTest. Build/test via the sandboxing `swift` wrapper already on PATH.

## Global Constraints

- **Zero third-party dependencies** — hard acceptance criterion; SwiftUI/AppKit/XCTest only.
- **macOS 15+, Swift 6 language mode v6** on every target.
- **Visuals are owned by `docs/design_handoff/`** — no visual/layout changes beyond the toast fade (E1, duration 0.18s ease-in-out).
- **Public API stays source-compatible where stated**: `store.state` remains readable (as a computed snapshot); intent methods (`setCommitMessage`, `setDiffMode`, `setPendingRefName`) remain.
- **Verify builds by hand** — never trust a summary line: `swift build 2>&1 | grep -E "error:|Linking"` must show `Linking` and no `error:`.
- **Screenshots need window-server access** — run `--shot` commands with sandbox disabled (Bash `dangerouslyDisableSandbox: true`).
- Tests: `swift test` runs 100+ tests incl. real-git integration; the store/parser tests are the fast harness: `swift test --filter GitWorkbenchTests`.
- Commit after every task (working code only). Branch: all work on `swiftui-review-fixes` off `main`.

---

### Task 0: Branch

**Files:** none (git only)

- [ ] **Step 1: Create the working branch**

```bash
cd /Users/gustavoambrozio/Development/GitWorkbench
git checkout -b swiftui-review-fixes
```

- [ ] **Step 2: Baseline — build + fast tests green before touching anything**

Run: `swift build 2>&1 | grep -E "error:|Linking"` → expect `Linking .../GitWorkbenchLiveDemo` lines, no `error:`.
Run: `swift test --filter GitWorkbenchTests 2>&1 | tail -5` → expect `Test Suite 'All tests' passed`.

---

### Task 1 (A1 part 1): Granular store properties + compatibility snapshot

**Files:**
- Modify: `Sources/GitWorkbench/Store/GitWorkbenchStore.swift`
- Test: `Tests/GitWorkbenchTests/StoreReducerTests.swift` (add one test; the existing 142 `store.state.*` assertions are the regression harness and must stay untouched)

**Interfaces:**
- Produces (later tasks + views rely on these exact names): stored `public private(set)` properties on `GitWorkbenchStore`: `activeView: WorkspaceView`, `diffMode: DiffMode`, `repo: RepositoryStatus`, `branches: [Branch]`, `remoteBranches: [RemoteBranch]`, `selectedFileID: FileChange.ID?`, `commitMessage: String`, `pendingDiscard: FileChange?`, `commits: [Commit]`, `selectedCommitID: Commit.ID?`, `selectedCommitFileID: FileChange.ID?`, `pendingRefCreation: PendingRefCreation?`, `pendingHardReset: Commit?`, `historyBranch: String?`, `isLoadingHistory: Bool`, `stashes: [Stash]`, `selectedStashID: Stash.ID?`, `selectedStashFileID: FileChange.ID?`, `currentDiff: FileDiff?`, `isBusy: Bool`, `toast: Toast?`.
- Produces computed: `staged: [FileChange]`, `unstaged: [FileChange]`, `canCommit: Bool`, `isBrowsingOtherBranch: Bool`, and `state: WorkbenchState` (read-only snapshot).
- Produces internal: `func apply(_ snapshot: WorkbenchState)` (preview/test seeding).
- `WorkbenchState` struct itself is **unchanged** (it stays as the snapshot type).

- [ ] **Step 1: Write the failing test** (append to `StoreReducerTests.swift`)

```swift
@MainActor
func test_granularPropertiesMirrorSnapshot() async {
    let store = GitWorkbenchStore(provider: MockGitProvider())
    await store.reload()
    store.setCommitMessage("hello")
    // Granular properties and the compatibility snapshot must agree.
    XCTAssertEqual(store.commits, store.state.commits)
    XCTAssertEqual(store.repo, store.state.repo)
    XCTAssertEqual(store.commitMessage, "hello")
    XCTAssertEqual(store.state.commitMessage, "hello")
    XCTAssertEqual(store.staged, store.state.staged)
    XCTAssertEqual(store.canCommit, store.state.canCommit)
}
```

- [ ] **Step 2: Run it — expect FAIL** (`value of type 'GitWorkbenchStore' has no member 'commits'` — a compile failure is the failing state here)

Run: `swift test --filter StoreReducerTests/test_granularPropertiesMirrorSnapshot 2>&1 | tail -20`

- [ ] **Step 3: Refactor the store.** In `GitWorkbenchStore.swift`:

**(a)** Replace `public private(set) var state: WorkbenchState` with the stored-property block:

```swift
// MARK: Granular UI state
//
// Each field is its own @Observable-tracked stored property, so a view that reads
// only `commits` is untouched by a commit-message keystroke or a toast. `state`
// (below) recomposes the full WorkbenchState snapshot for tests, demos, and
// headless hosts — reading it observes *everything*, so views use the fields.

public private(set) var activeView: WorkspaceView
public private(set) var diffMode: DiffMode
public private(set) var repo: RepositoryStatus
public private(set) var branches: [Branch] = []
public private(set) var remoteBranches: [RemoteBranch] = []
public private(set) var selectedFileID: FileChange.ID?
public private(set) var commitMessage: String = ""
public private(set) var pendingDiscard: FileChange?
public private(set) var commits: [Commit] = []
public private(set) var selectedCommitID: Commit.ID?
public private(set) var selectedCommitFileID: FileChange.ID?
public private(set) var pendingRefCreation: PendingRefCreation?
public private(set) var pendingHardReset: Commit?
public private(set) var historyBranch: String?
public private(set) var isLoadingHistory = false
public private(set) var stashes: [Stash] = []
public private(set) var selectedStashID: Stash.ID?
public private(set) var selectedStashFileID: FileChange.ID?
public private(set) var currentDiff: FileDiff?
public private(set) var isBusy = false
public private(set) var toast: Toast?

// MARK: Derived (same definitions WorkbenchState carries for snapshot consumers)

public var staged: [FileChange] { repo.files.filter(\.isStaged) }
public var unstaged: [FileChange] { repo.files.filter { !$0.isStaged } }
public var canCommit: Bool {
    !staged.isEmpty &&
    !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
public var isBrowsingOtherBranch: Bool {
    guard let historyBranch else { return false }
    return historyBranch != repo.currentBranch
}

// MARK: Compatibility snapshot

/// The full UI state recomposed as a value. Kept for tests, demos, and hosts that
/// want one Sendable snapshot. Reading this in a SwiftUI body observes every field —
/// views should read the individual properties instead.
public var state: WorkbenchState {
    var s = WorkbenchState(repo: repo)
    s.activeView = activeView; s.diffMode = diffMode
    s.branches = branches; s.remoteBranches = remoteBranches
    s.selectedFileID = selectedFileID; s.commitMessage = commitMessage
    s.pendingDiscard = pendingDiscard
    s.commits = commits; s.selectedCommitID = selectedCommitID
    s.selectedCommitFileID = selectedCommitFileID
    s.pendingRefCreation = pendingRefCreation; s.pendingHardReset = pendingHardReset
    s.historyBranch = historyBranch; s.isLoadingHistory = isLoadingHistory
    s.stashes = stashes; s.selectedStashID = selectedStashID
    s.selectedStashFileID = selectedStashFileID
    s.currentDiff = currentDiff
    s.isBusy = isBusy; s.toast = toast
    return s
}

/// Seed every field from a snapshot (previews, demos, tests).
func apply(_ snapshot: WorkbenchState) {
    activeView = snapshot.activeView; diffMode = snapshot.diffMode
    repo = snapshot.repo; branches = snapshot.branches; remoteBranches = snapshot.remoteBranches
    selectedFileID = snapshot.selectedFileID; commitMessage = snapshot.commitMessage
    pendingDiscard = snapshot.pendingDiscard
    commits = snapshot.commits; selectedCommitID = snapshot.selectedCommitID
    selectedCommitFileID = snapshot.selectedCommitFileID
    pendingRefCreation = snapshot.pendingRefCreation; pendingHardReset = snapshot.pendingHardReset
    historyBranch = snapshot.historyBranch; isLoadingHistory = snapshot.isLoadingHistory
    stashes = snapshot.stashes; selectedStashID = snapshot.selectedStashID
    selectedStashFileID = snapshot.selectedStashFileID
    currentDiff = snapshot.currentDiff
    isBusy = snapshot.isBusy; toast = snapshot.toast
}
```

**(b)** `init`: replace the `var initial = WorkbenchState(...)` block with direct assignments:

```swift
public init(provider: any GitWorkbenchProvider, configuration: WorkbenchConfiguration = .init()) {
    self.provider = provider
    self.configuration = configuration
    repo = RepositoryStatus(
        repositoryName: "", currentBranch: "", upstream: nil,
        ahead: 0, behind: 0, files: [], author: Author(name: "", initials: "")
    )
    activeView = configuration.initialView
    diffMode = Self.loadDiffMode(configuration) ?? configuration.defaultDiffMode
}
```

**(c)** Mechanical rewrite of every method body: `state.<field>` → `<field>`. Exhaustive list of methods to touch: `reload`, `summary` (becomes `hasLoaded ? RepositorySummary(repo, isBusy: isBusy) : nil`), `reloadFromExternalChange`, `reloadHistory`, `showHistory(ofRef:)`, `select(_:)`, `setDiffMode`, `setCommitMessage`, `select(file:)`, `loadDiff(for:context:)`, `setError`, `preview` (use `store.apply(seeded)` instead of `store.state = seeded`), `toggleStage`, `stageAll`, `unstageAll`, `requestDiscard`, `cancelDiscard`, `confirmDiscard`, `commit`, `runSync`, `syncCurrentBranchDivergence`, `switchBranch`, `checkoutRemoteBranch`, `selectCommitFile`, `selectStashFile`, `showToast`, `selectCommit`, `selectStash`, `applyStash`, `popStash`, `dropStash`, `checkout`, `resetHEAD`, `revert`, `cherryPick`, `requestHardReset`, `cancelHardReset`, `confirmHardReset`, `requestCreateBranch`, `requestCreateTag`, `setPendingRefName` (becomes `pendingRefCreation?.name = name`), `cancelRefCreation`, `confirmRefCreation`, `removeStashAndReselect`. Derived reads inside methods (`state.staged`, `state.unstaged`, `state.canCommit`) become `staged` / `unstaged` / `canCommit`.

- [ ] **Step 4: Build and run the full fast suite — everything must pass unchanged**

Run: `swift build 2>&1 | grep -E "error:|Linking"` → `Linking`, no errors (views still compile: `store.state` now resolves to the computed snapshot).
Run: `swift test --filter GitWorkbenchTests 2>&1 | tail -5` → `passed`. The new test passes too.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Store/GitWorkbenchStore.swift Tests/GitWorkbenchTests/StoreReducerTests.swift
git commit -m "refactor(store): split monolithic state into per-field @Observable properties (A1 1/2)

state remains as a computed compatibility snapshot; behavior unchanged."
```

---

### Task 2 (A1 part 2): Migrate views off `store.state`

**Files (every view that reads `store.state` — exhaustive):**
- Modify: `Sources/GitWorkbench/GitWorkbenchView.swift`
- Modify: `Sources/GitWorkbench/Views/Toolbar/WorkbenchToolbar.swift`
- Modify: `Sources/GitWorkbench/Views/Rail/WorkspaceRail.swift`
- Modify: `Sources/GitWorkbench/Views/Changes/ChangesBody.swift`, `ChangesFileList.swift`, `FileListRow.swift`, `CommitComposer.swift`, `ChangesDiffPane.swift`
- Modify: `Sources/GitWorkbench/Views/History/HistoryBody.swift`, `CommitGraphRow.swift`, `CommitDetail.swift`
- Modify: `Sources/GitWorkbench/Views/Stash/StashBody.swift`, `StashRow.swift`, `StashDetail.swift`
- Modify: `Sources/GitWorkbench/Views/Shared/DetailFiles.swift`, `NewRefPopover.swift`

**Interfaces:**
- Consumes: Task 1's granular properties.
- Rule: in **view** code, every `store.state.X` becomes `store.X`; every `s.X` (from `let s = store.state`) becomes a direct `store.X` read. Demos and tests are NOT touched (snapshot reads are fine there).

- [ ] **Step 1: Apply the mechanical rewrite.** Notes beyond pure find-and-replace:

  - `WorkbenchToolbar`: delete `let s = store.state`; use `store.repo.repositoryName`, `store.repo.behind`, `store.repo.ahead`, `store.isBusy`, and `store.state.diffMode` in the private `diffMode` binding becomes `store.diffMode` (binding rewritten fully in Task 5).
  - `WorkspaceRail`: delete `let s = store.state` at the top of `body`; replace uses with `store.branches`, `store.remoteBranches`, `store.repo`, `store.commits.count`, `store.stashes.count`, `store.activeView`, `store.historyBranch`. The two row helpers change signature — replace `state s: WorkbenchState` with the two values they use:

    ```swift
    private func localBranchRow(_ branch: Branch, displayName: String, indent: CGFloat) -> some View {
        let isCurrent = branch.name == store.repo.currentBranch
        return RailItem(icon: IconLibrary.branch, title: displayName, count: nil,
                        selected: store.activeView == .history
                            && branch.name == (store.historyBranch ?? store.repo.currentBranch),
                        emphasized: isCurrent, badge: isCurrent ? "HEAD" : nil,
                        ahead: branch.ahead, behind: branch.behind, indent: indent,
                        doubleAction: { Task { await store.switchBranch(to: branch) } })
        { Task { await store.showHistory(of: branch) } }
        .help("Click to view history \u{00B7} double-click to switch")
    }

    private func remoteBranchRow(_ remote: RemoteBranch, displayName: String, indent: CGFloat) -> some View {
        RailItem(icon: IconLibrary.branch, title: displayName, count: nil,
                 selected: store.activeView == .history && remote.id == store.historyBranch,
                 emphasized: remote.id == store.repo.upstream, indent: indent,
                 doubleAction: { Task { await store.checkoutRemoteBranch(remote) } })
        { Task { await store.showHistory(of: remote) } }
        .help("Click to view history \u{00B7} double-click to check out")
    }
    ```

    (call sites drop the `state: s` argument), and the `.onChange` closure uses `store.repo.currentBranch` / `store.repo.upstream` / `store.remoteBranches`.
  - `GitWorkbenchView`: `store.state.activeView` → `store.activeView`; `store.state.toast` → `store.toast` (2 places incl. `toastOverlay`).
  - `CommitComposer`: `store.state.canCommit` → `store.canCommit`, `store.state.staged.count` → `store.staged.count`, `store.state.repo.currentBranch` → `store.repo.currentBranch`, `store.state.commitMessage` → `store.commitMessage` (binding body rewritten fully in Task 5; for now just swap the paths inside it).
  - `NewRefPopover`: `store.state.pendingRefCreation?.name` → `store.pendingRefCreation?.name`.
  - Everything else is a literal `store.state.` → `store.` swap.

- [ ] **Step 2: Prove no view still reads the snapshot**

Run: `grep -rn "store\.state" Sources/GitWorkbench --include="*.swift" | grep -v "Store/GitWorkbenchStore.swift"`
Expected: no output.

- [ ] **Step 3: Build, test, screenshot**

Run: `swift build 2>&1 | grep -E "error:|Linking"` → `Linking`, no errors.
Run: `swift test --filter GitWorkbenchTests 2>&1 | tail -5` → `passed`.
Run (sandbox disabled): `.build/debug/GitWorkbenchDemo --shot /tmp/a1-changes.png --view changes && .build/debug/GitWorkbenchDemo --shot /tmp/a1-history.png --view history && .build/debug/GitWorkbenchDemo --shot /tmp/a1-stashes.png --view stashes`
Read all three PNGs — expect the standard three workspaces, visually unchanged (rail populated, diff rendered, no blank rows).

- [ ] **Step 4: Commit**

```bash
git add -A Sources/GitWorkbench
git commit -m "refactor(views): read granular store properties instead of the state snapshot (A1 2/2)"
```

---

### Task 3 (A2): `ColumnLayout` → `@Observable`

**Files:**
- Modify: `Sources/GitWorkbench/Views/Shared/ResizeDivider.swift:10-70` (class), `Sources/GitWorkbench/GitWorkbenchView.swift` (ownership + injection), `Sources/GitWorkbench/Views/Changes/ChangesBody.swift`, `Views/History/HistoryBody.swift`, `Views/Stash/StashBody.swift`, `Views/History/CommitDetail.swift` (consumers)

**Interfaces:**
- Produces: `@Observable @MainActor final class ColumnLayout` — same property/initializer names; injected via `.environment(layout)`, read via `@Environment(ColumnLayout.self)`.

- [ ] **Step 1: Convert the class**

```swift
import Observation

@Observable @MainActor
final class ColumnLayout {
    var railWidth: CGFloat { didSet { persist() } }
    var changesListWidth: CGFloat { didSet { persist() } }
    var historyListWidth: CGFloat { didSet { persist() } }
    var commitMessageHeight: CGFloat { didSet { persist() } }
    // …everything else in the class body is unchanged…
}
```

(Delete `: ObservableObject`; `@Published` wrappers become plain `var` with the same `didSet`s. Keep `import SwiftUI`.)

- [ ] **Step 2: Update owner and consumers**

`GitWorkbenchView`:

```swift
@State private var layout: ColumnLayout          // was @StateObject
public init(store: GitWorkbenchStore) {
    self.store = store
    _layout = State(initialValue: ColumnLayout(configuration: store.configuration))
}
// in body: .environment(layout)                 // was .environmentObject(layout)
```

Consumers (`ChangesBody`, `HistoryBody`, `StashBody`, `CommitDetail`):

```swift
@Environment(ColumnLayout.self) private var layout   // was @EnvironmentObject
```

Where a `Binding` is needed (`$layout.changesListWidth` / `$layout.historyListWidth` / `$layout.railWidth` for `ResizeDivider`), open the body with:

```swift
@Bindable var layout = layout
```

(`GitWorkbenchView` needs it for `$layout.railWidth`; `ChangesBody` for `$layout.changesListWidth`; `HistoryBody`/`StashBody` for `$layout.historyListWidth`. `CommitDetail` assigns `layout.commitMessageHeight` directly — no binding needed.)

- [ ] **Step 3: Build, test, screenshot** — same three commands as Task 2 Step 3 (shot names `/tmp/a2-*.png`); verify panes still lay out at the configured widths.

- [ ] **Step 4: Commit**

```bash
git add -A Sources/GitWorkbench
git commit -m "refactor: migrate ColumnLayout to @Observable for property-level invalidation (A2)"
```

---

### Task 4 (A4): `let store` + layout re-seed on persistence-key change

**Files:**
- Modify: `Sources/GitWorkbench/GitWorkbenchView.swift:5-13`

- [ ] **Step 1: Apply**

```swift
private let store: GitWorkbenchStore   // was: private var store
```

and on the root `VStack` in `body`, after `.workbenchTheme(theme)`:

```swift
// A host can swap stores at the same view identity (e.g. LiveDemo's Open…);
// @State layout would keep the first store's seeds. Re-identify on the
// persistence key so a different embedding context re-seeds its layout.
.id(configuration.persistenceKey)
```

- [ ] **Step 2: Build + fast tests** (`swift build`, `swift test --filter GitWorkbenchTests`) → green.

- [ ] **Step 3: Commit**

```bash
git add Sources/GitWorkbench/GitWorkbenchView.swift
git commit -m "fix: let-bind the store and re-seed layout when the persistence key changes (A4)"
```

---

### Task 5 (A3): Key-path bindings via `@Bindable`

**Files:**
- Modify: `Sources/GitWorkbench/Store/GitWorkbenchStore.swift` (bindable façades), `Views/Toolbar/WorkbenchToolbar.swift`, `Views/Changes/CommitComposer.swift`, `Views/Shared/NewRefPopover.swift`

**Interfaces:**
- Produces on the store: settable `commitMessage` (stored, drops `private(set)`; `setCommitMessage` kept), settable stored `diffMode` with `didSet { saveDiffMode(diffMode) }` (`setDiffMode` kept, body becomes `diffMode = mode`), and computed `public var pendingRefName: String`.

- [ ] **Step 1: Store façades**

```swift
public var commitMessage: String = ""            // was private(set); setter is a plain assignment
public var diffMode: DiffMode { didSet { saveDiffMode(diffMode) } }   // was private(set); didSet replaces setDiffMode's save
public func setDiffMode(_ mode: DiffMode) { diffMode = mode }         // kept as the intent API
public func setCommitMessage(_ text: String) { commitMessage = text } // unchanged

/// Bindable façade over the pending-ref name (TextField binding in NewRefPopover).
public var pendingRefName: String {
    get { pendingRefCreation?.name ?? "" }
    set { pendingRefCreation?.name = newValue }
}
```

(Note: `didSet` does not fire during `init`, so restoring the persisted mode in `init` does not write it back.) Remove the now-redundant `saveDiffMode` call from anywhere else.

- [ ] **Step 2: Views**

`WorkbenchToolbar` — delete the private `diffMode` computed Binding; in `body`:

```swift
@Bindable var store = store
…
Segmented(value: $store.diffMode, options: [ … ])
```

`CommitComposer` — delete `messageBinding`; in `body`:

```swift
@Bindable var store = store
…
TextEditor(text: $store.commitMessage)
```

`NewRefPopover` — delete `nameBinding`; in `body` add `@Bindable var store = store`, use `TextField(placeholder, text: $store.pendingRefName)`, and:

```swift
private var canCreate: Bool {
    !store.pendingRefName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
```

- [ ] **Step 3: Build + fast tests** → green (diff-mode persistence tests in `StoreReducerTests` cover the `didSet` path).

- [ ] **Step 4: Commit**

```bash
git add -A Sources/GitWorkbench
git commit -m "refactor: replace closure Bindings with @Bindable key-path bindings (A3)"
```

---

### Task 6 (B1): Hoist `SplitDiffBody`'s per-tick work into `init`

**Files:**
- Modify: `Sources/GitWorkbench/Views/Diff/SplitDiff.swift:29-67`

**Interfaces:**
- Consumes: `DiffSplitter.rows(_:) -> [SplitRow]`, `DiffMetrics.maxCodeWidth(_:)` (both unchanged).

- [ ] **Step 1: Restructure**

```swift
/// One hunk paired with its derived split rows, computed once per diff (not per body
/// pass — body re-runs on every horizontal scroll tick via `hOffset`).
private struct HunkRows: Identifiable {
    let hunk: DiffHunk
    let rows: [SplitRow]
    var id: DiffHunk.ID { hunk.id }
}

struct SplitDiffBody: View {
    @Environment(\.workbenchTheme) private var theme
    let diff: FileDiff
    private let maxCode: CGFloat
    private let hunkRows: [HunkRows]
    @State private var hOffset: CGFloat = 0

    init(diff: FileDiff) {
        self.diff = diff
        // Derived once per diff: init runs only when DiffView's body executes (file /
        // mode / theme change), while body runs on every scroll tick.
        self.maxCode = DiffMetrics.maxCodeWidth(diff)
        self.hunkRows = diff.hunks.map { HunkRows(hunk: $0, rows: DiffSplitter.rows($0.lines)) }
    }

    var body: some View {
        // was: let maxCode = DiffMetrics.maxCodeWidth(diff)  ← delete
        return GeometryReader { geo in
            …
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(hunkRows) { entry in
                            HunkHeaderBand(text: entry.hunk.header)
                            ForEach(entry.rows) { row in
                                SplitDiffRow(row: row, paneWidth: paneWidth, codeWidth: codeWidth, codeOffset: offset)
                            }
                        }
                    }
            …
        }
    }
    // scrollBars/barCell unchanged
}
```

- [ ] **Step 2: Run the splitter + full fast tests**

Run: `swift test --filter DiffSplitterTests 2>&1 | tail -3` → passed.
Run: `swift test --filter GitWorkbenchTests 2>&1 | tail -3` → passed.

- [ ] **Step 3: Visual check (split mode is the changed path)**

Run (sandbox disabled): `.build/debug/GitWorkbenchDemo --shot /tmp/b1-split.png --view changes --mode split && .build/debug/GitWorkbenchDemo --shot /tmp/b1-unified.png --view changes --mode unified`
Read both — split panes render rows/gutters/scroll strip as before.

- [ ] **Step 4: Commit**

```bash
git add Sources/GitWorkbench/Views/Diff/SplitDiff.swift
git commit -m "perf(diff): derive split rows and max code width once per diff, not per scroll tick (B1)"
```

---

### Task 7 (B2): Extract the rail's branch sections into a value-diffable child

**Files:**
- Modify: `Sources/GitWorkbench/Views/Rail/WorkspaceRail.swift`

**Interfaces:**
- Produces: `private struct RailBranchesSection: View` with **value** inputs (all Equatable) + the store for intents only: `store: GitWorkbenchStore`, `branches: [Branch]`, `remoteBranches: [RemoteBranch]`, `currentBranch: String`, `upstream: String?`, `activeView: WorkspaceView`, `historyBranch: String?`, `railCollapsed: Set<String>`, `repoID: String`.

- [ ] **Step 1: Restructure `WorkspaceRail`.** `body` keeps only the WORKSPACE header + three `RailItem`s and delegates everything from `railHeader("BRANCHES")` down (including the remote section, `Spacer`, and the `.onChange(of: collapseKey…)` collapse bookkeeping) to:

```swift
RailBranchesSection(store: store,
                    branches: store.branches,
                    remoteBranches: store.remoteBranches,
                    currentBranch: store.repo.currentBranch,
                    upstream: store.repo.upstream,
                    activeView: store.activeView,
                    historyBranch: store.historyBranch,
                    railCollapsed: store.railCollapsed,
                    repoID: repoID)
```

`RailBranchesSection` owns: the `localTree` / `remoteTrees` derivation, `CollapseSignature` + `.onChange`, `allCollapsibleFolders`, `railHeader("BRANCHES")` / `railHeader("REMOTES")`, and the two branch-row helpers (which now use the passed values: `currentBranch`, `activeView`, `historyBranch`, `upstream` — not `store.repo…`). The store reference is used **only** inside action closures (`store.toggleRailFolder`, `store.showHistory`, `store.switchBranch`, `store.checkoutRemoteBranch`, `store.applyRailCollapseDefaults`). Move `railHeader` to file scope (it's used by both structs) as `func railHeader(_ title: String, theme: WorkbenchTheme) -> some View` or duplicate it in the child — duplicating the 6-line helper inside the child is acceptable; do that (the parent keeps its copy for "WORKSPACE").

Because every stored property except `store` is Equatable and `store` is a stable class reference, SwiftUI skips the child's body — and therefore the tree building — whenever the branch-related inputs are unchanged (e.g. commit-message keystrokes, stage toggles, toasts). Update the now-stale "Derived once per body pass" comment to say the derivation lives in a child whose body is skipped when branch inputs don't change.

- [ ] **Step 2: Build, fast tests, screenshots** — `/tmp/b2-changes.png` (rail visible) plus `/tmp/b2-history.png`. Verify branch tree renders: folders, HEAD badge, remotes section.

- [ ] **Step 3: Commit**

```bash
git add Sources/GitWorkbench/Views/Rail/WorkspaceRail.swift
git commit -m "perf(rail): build branch trees in a value-diffable child so unrelated state changes skip it (B2)"
```

---

### Task 8 (B3): Rows take `selected:` instead of reading the store

**Files:**
- Modify: `Sources/GitWorkbench/Views/Changes/FileListRow.swift`, `Views/Changes/ChangesFileList.swift`, `Views/History/CommitGraphRow.swift`, `Views/History/HistoryBody.swift`, `Views/Stash/StashRow.swift`, `Views/Stash/StashBody.swift`

**Interfaces:**
- Produces: `FileListRow(store:file:selected:)`, `CommitGraphRow(store:commit:selected:)`, `StashRow(store:stash:selected:)` — `selected: Bool` is a new `let` on each; the row bodies read **no** store state (store stays for intents only).

- [ ] **Step 1: Apply to each pair**

`FileListRow`: add `let selected: Bool`; delete `let selected = store.state.selectedFileID == file.id` (post-Task-2: `store.selectedFileID`) from `body`. `ChangesFileList.group(...)`:

```swift
let selectedID = store.selectedFileID   // read once, at the top of body
…
ForEach(files) { file in
    FileListRow(store: store, file: file, selected: file.id == selectedID)
        .id("\(file.isStaged ? "s" : "u"):\(file.id)")
}
```

(`group(...)` gains a `selectedID: FileChange.ID?` parameter, or reads the top-of-`body` local — pass it as a parameter.)

`CommitGraphRow`: add `let selected: Bool`; delete the `let selected = …` line. `HistoryBody`:

```swift
let selectedCommitID = store.selectedCommitID
…
ForEach(store.commits) { CommitGraphRow(store: store, commit: $0, selected: $0.id == selectedCommitID) }
```

Note: `CommitGraphRow`'s context menu keeps `store.isBrowsingOtherBranch` — menu content is built on demand, not during `body`, so it adds no body dependency.

`StashRow`: same pattern with `store.selectedStashID` in `StashBody`.

- [ ] **Step 2: Build, fast tests, screenshots** — `/tmp/b3-changes.png --select src/commands/sync.ts`, `/tmp/b3-history.png`, `/tmp/b3-stashes.png`. Verify the selected row is accent-filled in each list.

- [ ] **Step 3: Commit**

```bash
git add -A Sources/GitWorkbench/Views
git commit -m "perf(rows): pass selection down as a value so only affected rows re-evaluate (B3)"
```

---

### Task 9 (B6): Confine the interactions environment read to a mouse-layer child

**Files:**
- Modify: `Sources/GitWorkbench/Views/Changes/FileListRow.swift`, `Views/Changes/ChangesFileList.swift`

**Interfaces:**
- Produces: `private struct FileRowMouseLayer: View` in `FileListRow.swift` — inputs `fileURL: URL`, `exclusions: [CGRect]` (Equatable); owns the `@Environment(\.changesFileInteractions)` read, the `popover` state, and the catcher.
- `FileListRow` gains `let repositoryRoot: URL?` (passed by `ChangesFileList` from `store.configuration.repositoryURL`) and loses its `@Environment(\.changesFileInteractions)` and `popover` state.

- [ ] **Step 1: Extract**

```swift
/// Owns the host-interaction plumbing so only this leaf depends on the closure-holding
/// (uncomparable) environment key — FileListRow itself stays value-diffable.
private struct FileRowMouseLayer: View {
    @Environment(\.changesFileInteractions) private var interactions
    let fileURL: URL
    let exclusions: [CGRect]
    @State private var popover: PopoverContent?

    private struct PopoverContent: Identifiable {
        let id = UUID()
        let view: AnyView
    }

    var body: some View {
        ZStack {   // stable single root even when inactive
            if interactions.isActive {
                ChangesMouseCatcher(
                    onRightClick: interactions.handlesRightClick ? { handleRightClick() } : nil,
                    onDoubleClick: interactions.onDoubleClick != nil ? { interactions.onDoubleClick?(fileURL) } : nil,
                    doubleClickExclusions: exclusions
                )
            }
        }
        .popover(item: $popover, arrowEdge: .trailing) { $0.view }
    }

    private func handleRightClick() {
        interactions.onRightClick?(fileURL)
        if let make = interactions.rightClickPopover, let view = make(fileURL) {
            popover = PopoverContent(view: view)
        }
    }
}
```

`FileListRow`: delete `@Environment(\.changesFileInteractions)`, `@State private var popover`, `PopoverContent`, `mouseCatcher`, `handleRightClick`, `handleDoubleClick`, and the `.popover(item:)` modifier. Add `let repositoryRoot: URL?`; `fileURL` becomes `file.url(relativeTo: repositoryRoot)`. Replace `.overlay { mouseCatcher }` with:

```swift
.overlay { FileRowMouseLayer(fileURL: fileURL, exclusions: doubleClickExclusions) }
```

`ChangesFileList`: pass `repositoryRoot: store.configuration.repositoryURL` into `FileListRow` (read once at top of `body` like `selectedID`).

- [ ] **Step 2: Build + fast tests** → green.

- [ ] **Step 3: Behavior check with the live demo** (right-click popover + double-click open are host-wired there)

Run (sandbox disabled, from a real repo path): `.build/debug/GitWorkbenchLiveDemo --shot /tmp/b6-live.png --view changes /Users/gustavoambrozio/Development/GitWorkbench`
Read the PNG — Changes rows render. (Interactive right-click/double-click can't be scripted; the wiring is type-checked and the catcher install condition is unchanged. Flag for the user's smoke test.)

- [ ] **Step 4: Commit**

```bash
git add -A Sources/GitWorkbench/Views/Changes
git commit -m "perf(changes): isolate the closure-holding interactions env read in a leaf mouse layer (B6)"
```

---

### Task 10 (B4): Async image decode with a spinner *(user request: add spinner)*

**Files:**
- Modify: `Sources/GitWorkbench/Views/Diff/ImageDiffView.swift:18-45`

- [ ] **Step 1: Replace the decoding init with `@State` + `.task(id:)`**

```swift
/// Renders an image file. Added/deleted → the single image filling the pane; modified → the
/// before/after comparer. Bytes are decoded asynchronously per file (a spinner shows until
/// they're ready); `.id(file.id)` on the parent resets the decoded state per file.
struct ImageDiffView: View {
    let file: FileChange
    let content: BinaryContent
    @State private var decoded: Decoded?

    /// Decoded sides. `bothSidesHadBytes` distinguishes a real add/delete from a modification
    /// where one side failed to decode (corrupt blob / Git-LFS pointer).
    private struct Decoded {
        var old: NSImage?
        var new: NSImage?
        var bothSidesHadBytes: Bool
    }

    init(content: BinaryContent, file: FileChange) {
        self.content = content
        self.file = file
    }

    var body: some View {
        ZStack {
            if let decoded {
                if let old = decoded.old, let new = decoded.new {
                    ModifiedImageComparer(old: old, new: new)
                } else if !decoded.bothSidesHadBytes, let single = decoded.new ?? decoded.old {
                    ImageCanvas(image: single).padding(16)
                } else {
                    BinaryPlaceholder(file: file, caption: "Can\u{2019}t display image")
                }
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: file.id) {
            // NSImage isn't Sendable, so decode on the main actor — but yield first so the
            // spinner paints before the decode work runs, instead of blocking this body.
            await Task.yield()
            decoded = Decoded(old: content.old.flatMap { NSImage(data: $0) },
                              new: content.new.flatMap { NSImage(data: $0) },
                              bothSidesHadBytes: content.old != nil && content.new != nil)
        }
    }
}
```

(Everything below `// MARK: - Single image` is unchanged.)

- [ ] **Step 2: Build, fast tests, screenshot the image-diff fixture**

Run: `swift build 2>&1 | grep -E "error:|Linking"` → clean; `swift test --filter GitWorkbenchTests | tail -3` → passed.
Run (sandbox disabled): `.build/debug/GitWorkbenchDemo --shot /tmp/b4-image.png --view changes --select assets/banner.png`
Read the PNG — the before/after comparer renders (decode completes well within the shot's settle delay).

- [ ] **Step 3: Commit**

```bash
git add Sources/GitWorkbench/Views/Diff/ImageDiffView.swift
git commit -m "perf(diff): decode images asynchronously with a loading spinner (B4)"
```

---

### Task 11 (B5): Validate PDFs once, with the same spinner pattern

**Files:**
- Modify: `Sources/GitWorkbench/Views/Diff/PDFDiffView.swift:8-44`

- [ ] **Step 1: Apply**

```swift
struct PDFDiffView: View {
    let content: BinaryContent
    let file: FileChange
    @State private var validated: Validated?

    /// Sides that PDFKit confirmed parseable (nil side → placeholder logic below).
    private struct Validated {
        var old: Data?
        var new: Data?
    }

    var body: some View {
        ZStack {
            if let validated {
                if let oldData = validated.old, let newData = validated.new {
                    HStack(spacing: 14) {
                        labeled("Before", oldData)
                        labeled("After", newData)
                    }
                    .padding(16)
                } else if let data = validated.new ?? validated.old {
                    PDFDocumentView(data: data).padding(16)
                } else {
                    BinaryPlaceholder(file: file, caption: "Can\u{2019}t display PDF")
                }
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: file.id) {
            await Task.yield()   // let the spinner paint first (PDFDocument is main-actor here)
            validated = Validated(old: content.old.flatMap(renderablePDF),
                                  new: content.new.flatMap(renderablePDF))
        }
    }
    // renderablePDF, labeled, PDFDocumentView unchanged
}
```

- [ ] **Step 2: Build, fast tests, screenshot** — `.build/debug/GitWorkbenchDemo --shot /tmp/b5-pdf.png --view changes --select docs/spec.pdf` (use the PDF fixture path from `Fixtures.files`; check `grep -n "pdf" Sources/GitWorkbench/Provider/Fixtures.swift` for the exact path first). Read the PNG — side-by-side PDFs render.

- [ ] **Step 3: Commit**

```bash
git add Sources/GitWorkbench/Views/Diff/PDFDiffView.swift
git commit -m "perf(diff): validate PDF bytes once per file instead of per body pass (B5)"
```

---

### Task 12 (C1): Stable identity for ref pills

**Files:**
- Modify: `Sources/GitWorkbench/Views/History/CommitGraphRow.swift:26`

- [ ] **Step 1: Apply**

```swift
// was: ForEach(Array(commit.refs.enumerated()), id: \.offset) { _, ref in
ForEach(commit.refs, id: \.self) { ref in
    RefPill(ref: ref, selected: selected)
}
```

(`CommitRef` is `Hashable`; refs on one commit are unique by construction, so the element is its own stable id.)

- [ ] **Step 2: Build + screenshot** — `/tmp/c1-history.png --view history`; ref pills (HEAD/branch/tag) render on the fixture commits.

- [ ] **Step 3: Commit**

```bash
git add Sources/GitWorkbench/Views/History/CommitGraphRow.swift
git commit -m "fix(history): key ref pills by the ref itself, not its position (C1)"
```

---

### Task 13 (D1): Button semantics for selectable rows

**Files:**
- Modify: `Sources/GitWorkbench/Views/History/CommitGraphRow.swift`, `Views/Stash/StashRow.swift`, `Views/Changes/FileListRow.swift`, `Views/Rail/WorkspaceRail.swift` (RailItem)

- [ ] **Step 1: `CommitGraphRow` + `StashRow` (no nested controls — plain Button wrap).** Pattern for both:

```swift
var body: some View {
    Button { Task { await store.selectCommit(commit.id) } } label: {
        rowContent                     // the existing HStack/VStack, unchanged
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
    .contextMenu { contextMenu }       // CommitGraphRow only
}
```

Extract the current body content into `private var rowContent: some View` and delete the old `.onTapGesture`. Keep `.contentShape` inside the label so the whole row stays clickable.

- [ ] **Step 2: `FileListRow` (nested stage box + discard button).** Same Button wrap around the existing HStack with the action `store.select(file: file.id)`; the `.coordinateSpace`, `.overlay(FileRowMouseLayer…)`, `.onPreferenceChange`, and `.onHover` modifiers stay OUTSIDE the Button. The nested `StageBox` tap gesture and hover discard `Button` sit inside a `.plain` button label; inner interactive views win the click on macOS, but this must be verified (Step 4).

- [ ] **Step 3: `RailItem` double-action path — accessibility without changing pointer behavior** (stacked tap gestures have no Button equivalent that preserves single+double):

```swift
if let doubleAction {
    label
        .onTapGesture(count: 2, perform: doubleAction)
        .onTapGesture(count: 1, perform: action)
        // Stacked tap gestures aren't exclusive: the single-click action also fires en
        // route to a double-click (showHistory is idempotent, so that's harmless).
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .accessibilityAction(named: "Switch to this branch") { doubleAction() }
} else { … }
```

(The named action reads "Switch to this branch" for local rows and doubles as check-out for remote rows; if that copy matters, add a `doubleActionName: String` parameter defaulting to `"Switch to this branch"` and pass "Check out this branch" from `remoteBranchRow`.) Do the parameter version.

- [ ] **Step 4: Verify click behavior in the built demo.** Build, then run the mock demo interactively (sandbox disabled): `.build/debug/GitWorkbenchDemo` — click a file row (selects), click its stage box (toggles WITHOUT changing selection), hover → click discard (confirm card, not selection), double-click a rail branch. Then quit. **Fallback if the stage box now also selects the row:** revert FileListRow's Button wrap to the previous `.onTapGesture(perform:)` and instead add to the row: `.accessibilityElement(children: .combine)`, `.accessibilityAddTraits(.isButton)`, `.accessibilityAction { store.select(file: file.id) }`, `.accessibilityAction(named: "Discard changes") { store.requestDiscard(file.id) }` — keeping pointer behavior identical while still exposing semantics.

- [ ] **Step 5: Screenshots** — `/tmp/d1-changes.png`, `/tmp/d1-history.png`, `/tmp/d1-stashes.png`: selected-row accent, hover styling, and layout unchanged.

- [ ] **Step 6: Commit**

```bash
git add -A Sources/GitWorkbench/Views
git commit -m "a11y: give selectable rows real button semantics; expose rail double-click as a named action (D1)"
```

---

### Task 14 (D2): Checkbox semantics for the stage box

**Files:**
- Modify: `Sources/GitWorkbench/Views/Changes/FileListRow.swift:32-35`

- [ ] **Step 1: Apply at the use site**

```swift
StageBox(checked: file.isStaged)
    .contentShape(Rectangle())
    .onTapGesture { Task { await store.toggleStage(file.id) } }
    .changesRowDoubleClickExcluded(in: Self.rowSpace)
    .accessibilityRepresentation {
        Toggle("Staged", isOn: Binding(
            get: { file.isStaged },
            set: { _ in Task { await store.toggleStage(file.id) } }))
    }
```

(The closure Binding here is inside `accessibilityRepresentation` — it never participates in render diffing, so A3's rule doesn't apply.)

- [ ] **Step 2: Build + fast tests** → green. **Step 3: Commit**

```bash
git add Sources/GitWorkbench/Views/Changes/FileListRow.swift
git commit -m "a11y: expose the stage box as a Toggle to assistive tech (D2)"
```

---

### Task 15 (D3): Labels + selection trait for `Segmented`

**Files:**
- Modify: `Sources/GitWorkbench/Views/Shared/Segmented.swift`, `Views/Toolbar/WorkbenchToolbar.swift:32-35`, `Views/Diff/ImageDiffView.swift` (axis options)

**Interfaces:**
- Produces: `SegmentedOption` gains `var accessibilityLabel: String? = nil`.

- [ ] **Step 1: Component**

```swift
struct SegmentedOption<Value: Hashable>: Identifiable {
    var value: Value
    var icon: String? = nil
    var label: String? = nil
    /// Spoken label for icon-only segments (falls back to `label`).
    var accessibilityLabel: String? = nil
    var id: Value { value }
}
```

and in `Segmented`'s `ForEach`, on the `Button` after `.buttonStyle(.plain)`:

```swift
.accessibilityLabel(option.accessibilityLabel ?? option.label ?? "")
.accessibilityAddTraits(isSelected ? [.isSelected] : [])
```

and on the container `HStack` (after `.background(…)`): `.accessibilityElement(children: .contain)`.

- [ ] **Step 2: Call sites.** Toolbar:

```swift
Segmented(value: $store.diffMode, options: [
    .init(value: .unified, icon: IconLibrary.unifiedRows, accessibilityLabel: "Unified diff"),
    .init(value: .split, icon: IconLibrary.splitColumns, accessibilityLabel: "Split diff"),
])
```

ImageDiffView axis picker: `accessibilityLabel: "Vertical divider"` / `"Horizontal divider"` (the compare-mode options already carry visible labels).

- [ ] **Step 3: Build + fast tests → green. Commit**

```bash
git add -A Sources/GitWorkbench/Views
git commit -m "a11y: label icon-only segments and expose selection state (D3)"
```

---

### Task 16 (D4): Esc / Return on the confirm cards

**Files:**
- Modify: `Sources/GitWorkbench/Views/Shared/ConfirmDiscardPopover.swift:21-24`, `ConfirmResetPopover.swift:22-25`, `NewRefPopover.swift:46-51`

- [ ] **Step 1: Apply** (`.keyboardShortcut` on a wrapper assigns the shortcut to the button inside)

```swift
// ConfirmDiscardPopover
capsuleButton("Cancel", …) { store.cancelDiscard() }
    .keyboardShortcut(.cancelAction)
capsuleButton("Discard Changes", …) { Task { await store.confirmDiscard() } }
    .keyboardShortcut(.defaultAction)

// ConfirmResetPopover
capsuleButton("Cancel", …) { store.cancelHardReset() }
    .keyboardShortcut(.cancelAction)
capsuleButton("Discard & Reset", …) { Task { await store.confirmHardReset() } }
    .keyboardShortcut(.defaultAction)

// NewRefPopover — Return already belongs to the TextField's onSubmit; only add:
capsuleButton("Cancel", …) { store.cancelRefCreation() }
    .keyboardShortcut(.cancelAction)
```

- [ ] **Step 2: Build → clean. Step 3: Commit**

```bash
git add Sources/GitWorkbench/Views/Shared
git commit -m "a11y: Esc cancels and Return confirms the modal confirm cards (D4)"
```

---

### Task 17 (D5): Label the section-collapse chevrons

**Files:**
- Modify: `Sources/GitWorkbench/Views/Changes/ChangesFileList.swift:50-53`

- [ ] **Step 1: Apply**

```swift
Button { collapsed.wrappedValue.toggle() } label: {
    Image(systemName: collapsed.wrappedValue ? IconLibrary.chevronRight : IconLibrary.chevronDown)
        .font(.system(size: 10)).foregroundStyle(theme.ink3)
}
.buttonStyle(.plain)
.accessibilityLabel(collapsed.wrappedValue ? "Expand \(title)" : "Collapse \(title)")
```

- [ ] **Step 2: Build → clean. Step 3: Commit**

```bash
git add Sources/GitWorkbench/Views/Changes/ChangesFileList.swift
git commit -m "a11y: label the Staged/Changes collapse chevrons (D5)"
```

---

### Task 18 (D6): `defaultFocus` in NewRefPopover

**Files:**
- Modify: `Sources/GitWorkbench/Views/Shared/NewRefPopover.swift:57`

- [ ] **Step 1: Apply** — delete `.onAppear { focused = true }`; on the card `VStack` (the container holding the TextField) add:

```swift
.defaultFocus($focused, true)
```

- [ ] **Step 2: Verify focus actually lands** (this is the one focus API with platform quirks): build, run `.build/debug/GitWorkbenchDemo` (sandbox disabled), History → right-click a commit → "Create New Branch from …" → type immediately; characters must land in the field. If they don't, keep `.defaultFocus` and re-add the `.onAppear` write as a fallback with a comment (`// defaultFocus alone doesn't win in this overlay on macOS 15`).

- [ ] **Step 3: Commit**

```bash
git add Sources/GitWorkbench/Views/Shared/NewRefPopover.swift
git commit -m "fix: seed the new-ref field's focus declaratively with defaultFocus (D6)"
```

---

### Task 19 (E1): Animate the toast

**Files:**
- Modify: `Sources/GitWorkbench/GitWorkbenchView.swift:55-67`

- [ ] **Step 1: Apply** — give the transition a stable animated container:

```swift
@ViewBuilder
private var toastOverlay: some View {
    ZStack {   // stable container: insertions/removals inside it can animate
        if let toast = store.toast {
            ToastView(toast: toast)
                .padding(.bottom, Tokens.toastBottomInset)
                .transition(.opacity)
                .task(id: toast.id) {
                    guard toast.style != .progress else { return }
                    try? await Task.sleep(for: .seconds(2.2))
                    store.dismissToast()
                }
        }
    }
    .animation(.easeInOut(duration: 0.18), value: store.toast)
}
```

- [ ] **Step 2: Build + fast tests → green.** (Fade is hard to screenshot; the change is confined to the overlay and scoped by `value:`.)

- [ ] **Step 3: Commit**

```bash
git add Sources/GitWorkbench/GitWorkbenchView.swift
git commit -m "polish: fade the toast in and out (E1)"
```

---

### Task 20 (E2): Update CLAUDE.md's store description

**Files:**
- Modify: `CLAUDE.md` (Architecture section, the "Unidirectional data flow" bullet)

- [ ] **Step 1: Replace the stale sentence** ("`@MainActor GitWorkbenchStore` (`Store/`) is an `ObservableObject` holding `@Published private(set) var state: WorkbenchState`") with:

```markdown
- **Unidirectional data flow.** `@MainActor @Observable GitWorkbenchStore` (`Store/`) holds the UI
  state as **per-field `private(set)` stored properties** (`repo`, `commits`, `commitMessage`,
  `toast`, …) so views observe only the fields they read; `store.state` recomposes the full
  `WorkbenchState` value as a snapshot for tests/demos/headless hosts (reading it observes
  everything — don't use it in view bodies). Views are a pure function of the store's fields and
  hold no business logic; user intents are store methods that **optimistically** mutate state and
  call the provider (rolling back + surfacing a toast on error). `GitWorkbenchView(store:)` is the
  single public entry point; `.preview` is a mock-backed store.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: describe the store's @Observable per-field state in CLAUDE.md (E2)"
```

---

### Task 21: Final verification sweep

**Files:** none (verification only)

- [ ] **Step 1: Full test suite** (integration tests shell out to real git — slower)

Run: `swift test 2>&1 | tail -5` → `Test Suite 'All tests' passed`.

- [ ] **Step 2: Fresh build check per CLAUDE.md** — `swift build 2>&1 | grep -E "error:|Linking"` shows `Linking`, then `stat -f %Sm .build/arm64-apple-macosx/debug/GitWorkbenchLiveDemo` timestamp is current.

- [ ] **Step 3: Full screenshot matrix** (sandbox disabled), read each:

```bash
for v in changes history stashes; do
  .build/debug/GitWorkbenchDemo --shot /tmp/final-$v-light.png --view $v
  .build/debug/GitWorkbenchDemo --shot /tmp/final-$v-dark.png --view $v --dark
done
.build/debug/GitWorkbenchDemo --shot /tmp/final-unified.png --view changes --mode unified
.build/debug/GitWorkbenchDemo --shot /tmp/final-image.png --view changes --select assets/banner.png
```

Compare against pre-change expectations: identical layout/colors; no blank rows (LazyVStack identity), populated rail, rendered diffs.

- [ ] **Step 4: Interactive smoke** on the live demo against this repo (per CLAUDE.md, lazy-container bugs only surface live): launch `.build/debug/GitWorkbenchLiveDemo .` — toggle unified/split, stage/unstage a file (watch the row move between sections with correct checkbox), switch views, resize columns, drag the History message divider (must feel smooth — this exercises A2+B1).

- [ ] **Step 5: Use the superpowers:requesting-code-review skill** for a review of the whole branch diff before merging.
