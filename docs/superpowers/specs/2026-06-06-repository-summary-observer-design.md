# RepositorySummary Observer — Design

**Date:** 2026-06-06
**Status:** Approved, in implementation
**Branch:** `feature/repository-summary-observer`

## Problem

A host embedding `GitWorkbenchView` wants to reflect the repository's state in its
own chrome — a menu-bar item, dock badge, window title, sidebar badge — without
running `git` a second time or reaching into the store's internals. It needs the
component to hand it a small, stable summary of the current git changes and to
call it again whenever that summary changes.

## Solution

A new public view modifier, `onRepositorySummaryChange`, that takes a closure
receiving a `RepositorySummary` value. The closure is called once with the current
summary on appear, then once per *distinct* summary thereafter (deduplicated via
`Equatable`).

This is a **state-observation** callback, distinct in shape from the existing
*event* callbacks (`onChangesRightClick` / `onChangesDoubleClick`), but it reuses
the same injection convention: an environment value populated by the modifier,
with additive stacking so multiple host layers all fire.

### `RepositorySummary` value type

`Sendable, Hashable` snapshot (Hashable gives `Equatable`, which `.onChange`
requires). Every field is a pure function of `WorkbenchState` — no new git work.

| Field | Type | Derivation |
|---|---|---|
| `repositoryName` | `String` | `repo.repositoryName` |
| `currentBranch` | `String` | `repo.currentBranch` |
| `changedFileCount` | `Int` | `repo.files.count` |
| `stagedCount` | `Int` | files where `isStaged` |
| `unstagedCount` | `Int` | files where `!isStaged` |
| `hasConflicts` | `Bool` | any file `.status == .conflicted` |
| `additions` | `Int` | sum of `repo.files.additions` |
| `deletions` | `Int` | sum of `repo.files.deletions` |
| `ahead` | `Int` | `repo.ahead` |
| `behind` | `Int` | `repo.behind` |
| `needsPush` | `Bool` | `ahead > 0` |
| `needsPull` | `Bool` | `behind > 0` |
| `hasUpstream` | `Bool` | `repo.upstream != nil` |
| `isClean` | `Bool` | no changed files **and** `ahead == 0` **and** `behind == 0` |
| `isBusy` | `Bool` | `state.isBusy` (a pull/push/fetch in flight) |

- `init(_ status: RepositoryStatus, isBusy:)` does all the per-file deriving in one
  pass; internal `init(state: WorkbenchState)` is a thin convenience over it.
- The convenience flags (`changedFileCount`, `needsPush`, `needsPull`, `isClean`) are
  **computed** from the stored primitives, so they can't be passed inconsistently and
  `Hashable` hashes only the underlying state. The public memberwise `init` therefore
  takes only the primitives and stays accessible for hosts and tests.
- The store also exposes a headless `summary: RepositorySummary?` (see wiring below)
  so a host holding the `@Observable` store can read it directly, without mounting
  `GitWorkbenchView`.

### Modifier + environment plumbing

New file `Sources/GitWorkbench/Views/RepositorySummaryObserver.swift`, mirroring
`ChangesFileInteractions.swift`:

- `RepositorySummaryObserver` — `@unchecked Sendable` wrapper holding the optional
  closure (same justification as `ChangesFileInteractions`: host closure read in a
  view body and invoked on the main actor only).
- `EnvironmentKey` + `EnvironmentValues.repositorySummaryObserver` accessor.
- Public API:

  ```swift
  func onRepositorySummaryChange(_ action: @escaping (RepositorySummary) -> Void) -> some View
  ```

  Stacking is additive: applying it twice runs both closures (existing closure
  captured, then the new one), matching `onChangesRightClick`.

### Wiring in `GitWorkbenchView`

The store is `@Observable` and exposes a public `summary: RepositorySummary?` that
stays `nil` until the first successful load (`hasLoaded`) completes. `GitWorkbenchView`
drives the host observer off that property:

```swift
.onChange(of: store.summary, initial: true) { _, summary in
    if let summary { observer(summary) }
}
```

`initial: true` reads the current value immediately on appear (and after a repo
swap re-mounts the view), then fires once per distinct summary. Because the store
is `@Observable` and the body reads `store.summary`, the body re-evaluates on every
state mutation, so `.onChange` sees each new summary; identical summaries are deduped
for free.

Because `store.summary` is `nil` until the first load finishes, the `if let` guard
means the observer fires **only once a load has completed** — the pre-load empty
placeholder (branch `""`, `isClean == true`) is never delivered, so a host wiring a
window title / dock badge needs no `isEmpty` guard. This is the same nil-until-loaded
rule the headless `store.summary` follows, so the view-scoped modifier and a host that
reads `store.summary` directly behave identically.

### Demo

`LiveDemoApp.swift` `RootView` gains `.onRepositorySummaryChange { … }` that logs a
compact line (e.g. `"3 changed · ↑1 ↓0 · main"`) so the firing is observable live.

## Testing

- `RepositorySummaryTests` (XCTest, `@testable import GitWorkbench`): pure unit
  tests over hand-built `WorkbenchState` fixtures asserting every derived field —
  counts, staged/unstaged split, `hasConflicts`, churn totals, `needsPush`/
  `needsPull`, `hasUpstream`, `isClean` (including the "ahead but no files" case),
  and `isBusy`.
- The modifier's *firing/dedup* is verified live in the demo, consistent with the
  project's "no ViewInspector; verify SwiftUI visually" constraint.

## Non-goals / YAGNI

- No Combine `summaryPublisher` on the store (a non-SwiftUI escape hatch) — can be
  added later if a host needs it; the closure modifier covers the stated use case.
- No per-file detail in the summary; hosts that need files read `store.state`.

## Acceptance criteria

- Zero new third-party dependencies (hard constraint).
- `RepositorySummary` is `Sendable, Hashable`.
- `swift build` and `swift test` pass; new tests cover the derivation.
- Modifier composes additively and fires once-on-appear-then-on-change in the demo.
