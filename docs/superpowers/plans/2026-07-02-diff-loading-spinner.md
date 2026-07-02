# Diff Loading Spinner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a grace-period spinner in all three diff panes while a diff load is in flight, and an honest "Couldn't load diff" state when the load fails.

**Architecture:** An explicit `isLoadingDiff` flag on `GitWorkbenchStore` (mirrors `isLoadingHistory`), set at every site that starts a diff load and cleared inside `loadDiff`'s existing `!Task.isCancelled` guard so a cancelled stale task can't clear a newer load's flag. A shared `DiffLoadingIndicator` view stays invisible for a 200ms grace period, then shows a centered `ProgressView`. `ChangesDiffPane` and `DetailDiffArea` branch: matching diff → loading → failed → no selection.

**Tech Stack:** Swift 6 / SwiftUI (macOS 15+), XCTest. Spec: `docs/superpowers/specs/2026-07-02-diff-loading-spinner-design.md`.

## Global Constraints

- **Zero third-party dependencies**; macOS 15+, Swift 6 language mode v6.
- `isLoadingDiff` is **additive public API** (`public private(set)`); `WorkbenchState` (the snapshot struct) is NOT changed — like `hasLoaded`/`railCollapsed`, the flag lives outside the snapshot.
- Spinner style matches existing usage: `ProgressView().controlSize(.small)` (History list, image/PDF viewers).
- The 200ms grace period is a **private constant** in `DiffLoadingIndicator` — not a design-handoff token.
- Build/test through the sandboxing `swift` wrapper; verify raw logs per CLAUDE.md (grep `error:`, never trust the xcsift summary alone). Fast suite: `swift test --filter GitWorkbenchTests` — expect **171** tests after this plan (168 + 3 new), 0 failures.
- Work happens on branch `diff-loading-spinner` (already checked out, stacked on `swiftui-review-fixes`).

---

### Task 1: `isLoadingDiff` store flag

**Files:**
- Modify: `Sources/GitWorkbench/Store/GitWorkbenchStore.swift` (flag declaration near `isLoadingHistory`'s sibling properties; `select(file:)` ~line 324; `loadDiff` ~line 340; `selectCommit`/`selectStash`/`selectCommitFile`/`selectStashFile`/`removeStashAndReselect` in the intent extensions)
- Test: `Tests/GitWorkbenchTests/StoreReducerTests.swift` (append 3 tests)

**Interfaces:**
- Produces: `public private(set) var isLoadingDiff: Bool` on `GitWorkbenchStore` — Task 2's views read exactly this name.
- Consumes: existing `diffTask` (internal, awaitable in tests), `MockGitProvider(delay:)`, and the tests' existing `FailingProvider` (its `loadDiff` throws `Boom`).

- [ ] **Step 1: Write the three failing tests** (append to `StoreReducerTests.swift`, inside the `StoreReducerTests` class)

```swift
    // MARK: Diff-loading flag (spinner support)

    func test_isLoadingDiffDuringAndAfterLoad() async throws {
        let store = GitWorkbenchStore(provider: MockGitProvider(delay: .milliseconds(80)))
        await store.reload()
        let file = try XCTUnwrap(store.repo.files.first)
        store.select(file: file.id)
        XCTAssertTrue(store.isLoadingDiff)          // in flight
        await store.diffTask?.value
        XCTAssertFalse(store.isLoadingDiff)         // cleared on success
        XCTAssertEqual(store.currentDiff?.file.id, file.id)
    }

    func test_isLoadingDiffClearsOnFailure() async throws {
        let store = GitWorkbenchStore(provider: FailingProvider())  // loadDiff throws
        await store.reload()
        let file = try XCTUnwrap(store.repo.files.first)
        store.select(file: file.id)
        await store.diffTask?.value
        XCTAssertFalse(store.isLoadingDiff)         // failure must not spin forever
        XCTAssertNil(store.currentDiff)             // panes show "Couldn't load diff"
    }

    func test_isLoadingDiffSurvivesRapidReselection() async throws {
        let store = GitWorkbenchStore(provider: MockGitProvider(delay: .milliseconds(80)))
        await store.reload()
        let a = try XCTUnwrap(store.repo.files.first)
        let b = try XCTUnwrap(store.repo.files.dropFirst().first)
        store.select(file: a.id)
        let staleTask = store.diffTask
        store.select(file: b.id)                    // cancels A's load, starts B's
        XCTAssertTrue(store.isLoadingDiff)
        await staleTask?.value                      // A finishing (cancelled) must NOT clear the flag
        XCTAssertTrue(store.isLoadingDiff)
        await store.diffTask?.value
        XCTAssertFalse(store.isLoadingDiff)
        XCTAssertEqual(store.currentDiff?.file.id, b.id)
    }
```

- [ ] **Step 2: Run them — expect compile FAIL** (`has no member 'isLoadingDiff'`)

Run: `swift test --filter StoreReducerTests/test_isLoadingDiff 2>&1 | tail -15`

- [ ] **Step 3: Implement the flag.** In `GitWorkbenchStore.swift`:

**(a)** Declare it next to `currentDiff` in the granular-state block:

```swift
/// True while a diff load for the current selection is in flight (drives the
/// panes' loading spinner). Mirrors `isLoadingHistory`. Not part of the
/// `state` snapshot — like `hasLoaded`, it is transient store-side state.
public private(set) var isLoadingDiff = false
```

**(b)** `loadDiff(for:context:)` — clear inside the existing cancellation guard:

```swift
func loadDiff(for file: FileChange, context: DiffRequest.Context) async {
    let request = DiffRequest(file: file, context: context, mode: diffMode)
    let diff = try? await provider.loadDiff(request)
    if !Task.isCancelled {
        currentDiff = diff
        isLoadingDiff = false
    }
}
```

**(c)** Set/clear at every site that starts (or skips) a diff load — exhaustive list:

- `select(file: id)`: in the `guard … else` path add `isLoadingDiff = false` next to `currentDiff = nil`; before `diffTask?.cancel()` add `isLoadingDiff = true`.
- `selectCommit(_:)`: in the `if let first` branch set `isLoadingDiff = true` before `await loadDiff(for: first, context: .commit(id))`; in the `else` branch add `isLoadingDiff = false` next to `currentDiff = nil`.
- `selectStash(_:)`: same pattern as `selectCommit`.
- `selectCommitFile(_:)`: after the `guard` succeeds, set `isLoadingDiff = true` before `diffTask?.cancel()`. (A failed guard returns without touching the flag — a previous load may legitimately still be in flight.)
- `selectStashFile(_:)`: same pattern as `selectCommitFile`.
- `removeStashAndReselect(_:)`: in the `guard !stashes.isEmpty else` branch add `isLoadingDiff = false` next to `currentDiff = nil`; in the `if let first` branch set `isLoadingDiff = true` before `diffTask?.cancel()`; in its `else` branch add `isLoadingDiff = false` next to `currentDiff = nil`.

- [ ] **Step 4: Run the new tests, then the fast suite**

Run: `swift test --filter StoreReducerTests/test_isLoadingDiff 2>&1 | tail -6` → 3 tests, 0 failures.
Run: `swift test --filter GitWorkbenchTests 2>&1 | tee ${TMPDIR:-/tmp}/test.log | tail -3` then `grep -E "Executed .* tests" ${TMPDIR:-/tmp}/test.log | tail -2` → **171 tests, 0 failures**.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Store/GitWorkbenchStore.swift Tests/GitWorkbenchTests/StoreReducerTests.swift
git commit -m "feat(store): track in-flight diff loads with isLoadingDiff"
```

---

### Task 2: `DiffLoadingIndicator` + pane branching

**Files:**
- Create: `Sources/GitWorkbench/Views/Shared/DiffLoadingIndicator.swift`
- Modify: `Sources/GitWorkbench/Views/Changes/ChangesDiffPane.swift:10-25` (body), `Sources/GitWorkbench/Views/Shared/DetailFiles.swift:73-85` (`DetailDiffArea`)

**Interfaces:**
- Consumes: `store.isLoadingDiff` from Task 1; existing `EmptyState(icon:title:)` and `IconLibrary.file`.
- Produces: `struct DiffLoadingIndicator: View` (no parameters).

- [ ] **Step 1: Create the indicator view**

```swift
import SwiftUI

/// A centered spinner for in-flight diff loads. Invisible for a short grace
/// period so fast loads render directly with no spinner flash; only loads
/// still in flight after the grace period show it. (Behavioral constant, not
/// a design-handoff token.)
struct DiffLoadingIndicator: View {
    @State private var visible = false
    private static let gracePeriod: Duration = .milliseconds(200)

    var body: some View {
        ZStack {   // stable single root across the invisible→spinner flip
            if visible {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: Self.gracePeriod)
            visible = true
        }
    }
}
```

- [ ] **Step 2: Branch `ChangesDiffPane`.** Replace the inner `if let diff … else { Spacer() }` (currently lines 12-16) with:

```swift
                if let diff = store.currentDiff, diff.file.id == file.id {
                    DiffView(diff: diff, mode: store.diffMode)
                } else if store.isLoadingDiff {
                    DiffLoadingIndicator()
                } else {
                    // A file is selected but its diff never arrived: the load failed.
                    EmptyState(icon: IconLibrary.file, title: "Couldn\u{2019}t load diff")
                }
```

(The outer `if let file = selectedFile … else` branch with the clean-tree/select-a-file empty states is unchanged.)

- [ ] **Step 3: Branch `DetailDiffArea`** (in `DetailFiles.swift`). Replace its body with:

```swift
    var body: some View {
        if let diff = store.currentDiff, diff.file.id == selectedFileID {
            DiffView(diff: diff, mode: store.diffMode)
        } else if store.isLoadingDiff {
            DiffLoadingIndicator()
        } else if selectedFileID != nil {
            // A file is selected but its diff never arrived: the load failed.
            EmptyState(icon: IconLibrary.file, title: "Couldn\u{2019}t load diff")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyState(icon: IconLibrary.file, title: "Select a file to view changes")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
```

- [ ] **Step 4: Build + fast suite**

Run: `swift build 2>&1 | tee ${TMPDIR:-/tmp}/build.log | xcsift --format toon --warnings` then `grep -E "error:" ${TMPDIR:-/tmp}/build.log | head` (must be empty).
Run: `swift test --filter GitWorkbenchTests 2>&1 | tee ${TMPDIR:-/tmp}/test.log | tail -3` → 171 tests, 0 failures.

- [ ] **Step 5: Visual verification.** Loaded-state regression via screenshots (sandbox disabled): `.build/debug/GitWorkbenchDemo --shot /tmp/spin-changes.png --view changes && .build/debug/GitWorkbenchDemo --shot /tmp/spin-history.png --view history && .build/debug/GitWorkbenchDemo --shot /tmp/spin-stashes.png --view stashes` — read all three; diffs render as before (the shots capture *after* load, so they prove no regression; they cannot capture the 200-700ms spinner window). Then verify the spinner interactively: launch `.build/debug/GitWorkbenchDemo` (mock's 700ms latency), click between files — blank gap is replaced by a centered spinner appearing after ~200ms; History/Stash detail panes no longer flash "Select a file to view changes" during loads.

- [ ] **Step 6: Commit**

```bash
git add Sources/GitWorkbench/Views/Shared/DiffLoadingIndicator.swift Sources/GitWorkbench/Views/Changes/ChangesDiffPane.swift Sources/GitWorkbench/Views/Shared/DetailFiles.swift
git commit -m "feat(diff): grace-period loading spinner + visible failure state in all diff panes"
```

---

### Task 3: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Full suite** — `swift test 2>&1 | tail -3` → `Test Suite 'All tests' passed` (236 tests: 233 + 3 new).
- [ ] **Step 2: Fresh-binary check** — `stat -f %Sm .build/arm64-apple-macosx/debug/GitWorkbenchDemo` timestamp is current; raw build log shows no `error:`.
- [ ] **Step 3: Use superpowers:requesting-code-review** for a review of the branch diff (`swiftui-review-fixes..HEAD`).
