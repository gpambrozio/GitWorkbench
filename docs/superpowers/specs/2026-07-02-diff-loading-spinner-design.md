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

### Store: explicit `isLoadingDiff` and `didFailDiffLoad`

`GitWorkbenchStore` gains `public private(set) var isLoadingDiff = false` (additive API; mirrors the existing `isLoadingHistory` precedent). Explicit rather than derived ("selected but no matching diff") because a derived flag cannot distinguish loading from failed and would spin forever after a failure.

- Set `true` at every site that starts a diff task: `select(file:)`, `selectCommit(_:)`, `selectStash(_:)`, `selectCommitFile(_:)`, `selectStashFile(_:)`, `removeStashAndReselect(_:)`.
- Cleared (`false`) in `loadDiff(for:context:)` on completion, inside the existing `if !Task.isCancelled` guard — a cancelled stale task must not clear the flag for a newer in-flight load. Selection paths that end with *no* diff task (empty commit/stash, unknown file id) set it `false` (or never set it `true`).

A second flag, `public private(set) var didFailDiffLoad = false`, records whether the *most recent* load completed with no diff (the provider threw). `currentDiff` is a single shared slot across tabs, so "selection exists but `currentDiff` doesn't match" is ambiguous between a real failure and a stale cross-tab selection (e.g. the Changes tab's file is still selected while History shows a different diff) — `didFailDiffLoad` disambiguates. It is set in `loadDiff(for:context:)` alongside `isLoadingDiff = false` (`diff == nil`), and reset to `false` at every site that also touches `isLoadingDiff` outside `loadDiff` (both the "started a load" and the "no diff task, nil the selection" sites), so a new selection or a cleared selection always starts from a clean slate.

`selectCommit(_:)` and `selectStash(_:)` route their diff load through `diffTask` (cancel-then-await) exactly like `select(file:)`, rather than awaiting `loadDiff` directly — otherwise a stale load's completion could clear `isLoadingDiff`/overwrite `currentDiff` after a newer selection had already started loading (e.g. clicking commit A then B in quick succession).

### Shared view: `DiffLoadingIndicator`

New `Sources/GitWorkbench/Views/Shared/DiffLoadingIndicator.swift`: renders `Color.clear` for the first ~200ms (a `.task` that sleeps, then flips local `@State`), then a centered small `ProgressView` — the same visual as the History-list and image/PDF loading states. The 200ms constant is private to this view (behavioral, not a design-handoff token).

### Panes: branch on load state

`ChangesDiffPane` and `DetailDiffArea` render, in order of precedence:

1. Matching diff (`currentDiff.file.id == selectedID`) → `DiffView` (unchanged).
2. `store.isLoadingDiff` → `DiffLoadingIndicator`.
3. `store.didFailDiffLoad` → `EmptyState(icon: file, title: "Couldn't load diff")` — the real-failure state, now keyed on the explicit flag rather than inferred from "selected but no matching diff".
4. Otherwise → the pane's neutral state: `ChangesDiffPane` falls back to a blank `Spacer()` (the pre-feature default) and `DetailDiffArea` falls back to "Select a file to view changes". This covers both "nothing selected" and a stale cross-tab selection (a selection exists elsewhere but this pane's diff hasn't loaded and didn't fail) — neither is a lie the way an unconditional "Couldn't load diff" would be.

### Testing

Store tests with `MockGitProvider(delay:)` (nonzero delay): flag true mid-flight; false after success; false after failure (provider that throws); correct across a rapid selection switch (cancel + new load — flag stays true until the *new* load finishes). The 200ms visual delay is verified interactively in the demo (mock's 700ms latency makes it visible); no SwiftUI unit test per the zero-dependency constraint.

`didFailDiffLoad` is covered the same way: true after a `FailingProvider` load, false after a `MockGitProvider` success. The `selectCommit`/`selectStash` cancellation fix is covered by selecting commit A then B in quick succession (via `MockGitProvider(delay:)`) and asserting the settled state reflects B, not a clobber from A's late completion.

### Constraints

Zero third-party dependencies; macOS 15+/Swift 6 v6; visuals per design handoff (spinner style matches existing `ProgressView().controlSize(.small)` usage); `isLoadingDiff` and `didFailDiffLoad` are additive public API.
