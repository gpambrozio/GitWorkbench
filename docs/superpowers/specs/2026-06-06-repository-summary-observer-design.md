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

- Internal `init(state: WorkbenchState)` does all the deriving in one place.
- Memberwise `init` stays accessible so tests and hosts can build one directly.

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

In `body`, read the environment closure, compute
`RepositorySummary(state: store.state)`, and attach:

```swift
.onChange(of: summary, initial: true) { _, new in observer(new) }
```

`initial: true` delivers the current value immediately on appear (and after a repo
swap re-mounts the view), then one call per distinct summary. Because the view
already observes the store, its body re-evaluates on every state mutation, so
`.onChange` sees each new summary; identical summaries are deduped for free.

Note: the very first fire may reflect the pre-load empty state (branch `""`,
`isClean == true`) before `.task { reload() }` completes; the loaded summary fires
immediately after. This is expected for an observer and harmless for indicator use.

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
