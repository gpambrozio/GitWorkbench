# Diff Loading Spinner — Design

**Date:** 2026-07-02 · **Status:** approved (user, this session) · **Builds on:** branch `swiftui-review-fixes` (PR #16)

## Problem

Loading a diff is async (`store.loadDiff` → `provider.loadDiff`). While the load is in flight there is no loading representation anywhere:

- `ChangesDiffPane` renders the file header over a blank `Spacer()`.
- `DetailDiffArea` (History and Stash detail panes) shows the *misleading* "Select a file to view changes" empty state even though a file is selected and loading.
- `MockGitProvider` has **700ms artificial latency per call** (its default), so the demo shows a blank/misleading pane for 700ms on every selection; LiveDemo shows the same gap whenever real `git diff` is slow.
- A **failed** load is invisible: `loadDiff` uses `try?`, so failure leaves `currentDiff` nil and the pane blank forever, indistinguishable from "still loading".

## Goals

1. Show a spinner in all three diff panes while a diff load is in flight — but only if the load takes longer than ~200ms, so fast loads don't flash (user-selected behavior).
2. Make load *failure* visible: an honest "Couldn't load diff" empty state instead of an eternal blank.

Out of scope: provider/protocol changes; the synchronous split-row derivation cost (already once-per-diff after B1); binary-content spinners (already exist from B4/B5).

## Design

### Store: explicit `isLoadingDiff`

`GitWorkbenchStore` gains `public private(set) var isLoadingDiff = false` (additive API; mirrors the existing `isLoadingHistory` precedent). Explicit rather than derived ("selected but no matching diff") because a derived flag cannot distinguish loading from failed and would spin forever after a failure.

- Set `true` at every site that starts a diff task: `select(file:)`, `selectCommit(_:)`, `selectStash(_:)`, `selectCommitFile(_:)`, `selectStashFile(_:)`, `removeStashAndReselect(_:)`.
- Cleared (`false`) in `loadDiff(for:context:)` on completion, inside the existing `if !Task.isCancelled` guard — a cancelled stale task must not clear the flag for a newer in-flight load. Selection paths that end with *no* diff task (empty commit/stash, unknown file id) set it `false` (or never set it `true`).

### Shared view: `DiffLoadingIndicator`

New `Sources/GitWorkbench/Views/Shared/DiffLoadingIndicator.swift`: renders `Color.clear` for the first ~200ms (a `.task` that sleeps, then flips local `@State`), then a centered small `ProgressView` — the same visual as the History-list and image/PDF loading states. The 200ms constant is private to this view (behavioral, not a design-handoff token).

### Panes: branch on load state

`ChangesDiffPane` and `DetailDiffArea` render, in order of precedence:

1. Matching diff (`currentDiff.file.id == selectedID`) → `DiffView` (unchanged).
2. `store.isLoadingDiff` → `DiffLoadingIndicator`.
3. File selected but diff nil (load failed) → `EmptyState(icon: file, title: "Couldn't load diff")` — new state, previously an eternal blank.
4. No selection → existing empty states (unchanged).

### Testing

Store tests with `MockGitProvider(delay:)` (nonzero delay): flag true mid-flight; false after success; false after failure (provider that throws); correct across a rapid selection switch (cancel + new load — flag stays true until the *new* load finishes). The 200ms visual delay is verified interactively in the demo (mock's 700ms latency makes it visible); no SwiftUI unit test per the zero-dependency constraint.

### Constraints

Zero third-party dependencies; macOS 15+/Swift 6 v6; visuals per design handoff (spinner style matches existing `ProgressView().controlSize(.small)` usage); `isLoadingDiff` is additive public API.
