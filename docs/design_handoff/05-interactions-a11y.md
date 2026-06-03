# 05 — Interactions, State, Accessibility, Shortcuts & Tests

How the store reacts to intents, plus the non-visual requirements. Pair with
[01-architecture.md](01-architecture.md) (store API) and [03-views.md](03-views.md) (where each
control lives).

---

## 5.1 Intent → store → effect table

Every user action calls a `GitWorkbenchStore` intent method. The store updates `state`
optimistically where safe, calls the provider, then reconciles (or rolls back + error toast on
failure).

| Action | Intent | State change | Provider call | Toast |
|---|---|---|---|---|
| Select workspace view | `select(_:)` | `activeView = v` | — | — |
| Select file (Changes) | `select(file:)` | `selectedFileID`; load diff | `loadDiff(workingTree)` | — |
| Toggle stage | `toggleStage(_:)` | flip `isStaged` optimistically | `stage` / `unstage` | — (rollback + error toast on throw) |
| Stage all / Unstage all | `stageAll()` / `unstageAll()` | set all `isStaged` | `stage`/`unstage` (batch) | — |
| Request discard | `requestDiscard(_:)` | `pendingDiscard = file` | — | — |
| Confirm discard | `confirmDiscard()` | remove file; clear selection if it was selected; `pendingDiscard = nil` | `discard` | "Discarded changes in {name}" |
| Cancel discard | `cancelDiscard()` | `pendingDiscard = nil` | — | — |
| Edit message | `setCommitMessage(_:)` | `commitMessage` | — | — |
| Commit | `commit()` | guard `canCommit`; remove staged files; clear message; `repo.ahead += 1`; reselect | `commit(message:staged:)` | "Committed {n} files · "{summary}"" |
| Pull | `pull()` | `isBusy = true` → on result `behind = 0` | `pull()` | progress → "Pulled {n} commits from origin" |
| Push | `push()` | `isBusy = true` → on result `ahead = 0` | `push()` | progress → "Pushed {n} commits to origin" |
| Fetch | `fetch()` | `isBusy = true` | `fetch()` | progress → "Up to date with origin" / result message |
| Switch branch | `switchBranch(to:)` | `branchMenuOpen = false`; update current branch; reload status/history/stashes | `switchBranch` then reload | "Switched to {branch}" |
| Toggle diff mode | `setDiffMode(_:)` | `diffMode`; persist (see §5.3) | — | — |
| Select commit | `selectCommit(_:)` | `selectedCommitID`; select first file; load diff | `loadDiff(commit)` | — |
| Select stash | `selectStash(_:)` | `selectedStashID`; select first file; load diff | `loadDiff(stash)` | — |
| Apply stash | `applyStash(_:)` | (no list change) | `applyStash` | "Applied {ref} to working tree" |
| Pop stash | `popStash(_:)` | remove from `stashes`; reselect next | `popStash` | "Popped {ref} — "{message}"" |
| Drop stash | `dropStash(_:)` | remove from `stashes`; reselect next | `dropStash` | "Dropped {ref} — "{message}"" |

### Confirmation rule
Only **irreversible** operations confirm: **Discard**, **Drop stash**, branch delete, force-push.
Stage/unstage/commit/apply/pop are immediate (commit & pop are reversible via git) and never
interrupt with a dialog.

### Sync (pull/push/fetch) flow
1. If `isBusy`, ignore (buttons are also disabled).
2. `isBusy = true`; show a **progress** toast ("Pulling from origin…") with a spinner; no
   auto-dismiss (use a long 9s ceiling).
3. `await provider.{pull|push|fetch}()`.
4. On success: apply `SyncResult` (reset ahead/behind as appropriate), `isBusy = false`, replace the
   progress toast with the success toast (2.2s).
5. On failure: `isBusy = false`, replace with an **error** toast. Map "push rejected" →
   "Push rejected — pull first" when detectable.

---

## 5.2 State machine (per view)

- **Active view** is a 3-state enum (`changes`/`history`/`stashes`). Switching preserves each view's
  own selection (selected file, selected commit, selected stash) so returning to a view restores it.
- **Selection independence:** Changes' `selectedFileID`, History's
  `selectedCommitID`+`selectedCommitFileID`, and Stash's `selectedStashID`+`selectedStashFileID` are
  separate fields — never share one "selected file" across views.
- **Diff cache:** keep `currentDiff` keyed to the active view's current request; reload on selection
  or `diffMode` change only if needed (the renderer can re-derive split from unified, so a mode flip
  does **not** require a provider round-trip).

---

## 5.3 Persistence

Persist per-repository, keyed by repo identity (e.g. remote URL or path hash), via the host or
`UserDefaults` (suite-overridable through config):
- `diffMode` (unified/split).
- Optionally pane widths if the host enables resizing.
- Draft commit message (so it survives view switches within a session — keep in-memory at minimum).

Expose an optional `WorkbenchConfiguration.persistenceKey: String?`; when nil, don't persist.

---

## 5.4 Keyboard shortcuts

Wire via `.keyboardShortcut` / `commands` where the component owns focus. Scope to the workbench
view (don't steal global shortcuts).

| Keys | Action | Notes |
|---|---|---|
| ⌘↵ | Commit | only when `canCommit`; active while composer focused |
| ⌘⇧S | Stage all | Changes view |
| ⌘⌫ | Discard selected file | opens confirm |
| ⌘⇧K | Push | disabled while busy |
| ⌘⇧P | Pull | |
| ⌘R | Fetch / refresh | also `reload()` |
| ↑ / ↓ | Move selection in the active list | file list / commits / stashes |
| Space | Toggle stage on selected file | Changes view |
| ⌘B | Open branch switcher | focuses the menu |
| ⌘⌥D | Toggle Unified / Split | |
| Esc | Dismiss branch menu / confirm popover | |

Provide these as a documented `Commands` group the host can include, plus inline
`.keyboardShortcut`s on the buttons so they work without host wiring.

---

## 5.5 Accessibility

- **Labels & values:**
  - File row: `.accessibilityLabel("{status.label} {path}")`,
    `.accessibilityValue(isStaged ? "Staged" : "Not staged")`, with `+{add} −{del}` in the label.
  - Stage box: a real toggle — `.accessibilityAddTraits(.isToggle)` (or a `Toggle` styled to match),
    label "Stage {name}".
  - Status glyph is decorative when the row label already states status →
    `.accessibilityHidden(true)`.
  - Commit/Pull/Push/Fetch/Apply/Pop/Drop: clear labels; disabled state announced.
  - Diff lines: group each line as
    `"{added|removed|context} line {newNumber ?? oldNumber}: {text}"`; gutters hidden.
  - Avatar: label the author name; SHA chip: "Copy commit {shortSHA}".
- **Focus order:** toolbar → rail → list → composer (Changes) / detail (History/Stash) → diff.
- **Traits:** selected rows `.isSelected`; toolbar toggles reflect selected state.
- **Contrast:** the status/diff colors meet AA on their backgrounds; verify the Dark Mode variants.
- **Dynamic Type:** support at least up to XL — rows grow vertically rather than clipping; never
  hard-clip text. Diff stays monospaced but scales.
- **Reduce Motion:** drop toast translate + view cross-fade (see [04 §4.5]).
- **VoiceOver rotor:** expose list rows as a collection; diff hunks as headings (the `@@` header is
  an `.accessibilityAddTraits(.isHeader)`).
- **Full keyboard access:** every interactive element is reachable via Tab/arrows; the discard
  hover-action must also be reachable without hover (expose it in the diff header — it already is —
  and/or a context menu on the row).

---

## 5.6 Context menus (right-click)

- **File row:** Stage/Unstage, Discard…, Copy Path, Reveal in Finder (host-handled), Open in Editor
  (host-handled).
- **Commit row:** Copy SHA, Copy Message, Checkout {sha}…, Create Branch Here…, Revert…
  (host-handled actions are optional closures on the provider; omit if nil).
- **Stash row:** Apply, Pop, Drop, Create Branch From Stash.
- **Branch (rail/menu):** Switch, Merge into current…, Rename…, Delete… (destructive confirm).

Expose host-optional actions as nullable closures in `WorkbenchConfiguration`
(e.g. `var onRevealInFinder: ((FileChange) -> Void)?`); hide menu items whose closure is nil.

---

## 5.7 Tests

`Tests/GitWorkbenchTests`:

- **`DiffSplitterTests`** — given known hunks, assert:
  - unified line ordering + correct `oldNumber`/`newNumber` assignment for context/add/del;
  - split pairing (deletions↔additions zipped, padded; context on both sides);
  - pure-add and pure-delete files.
- **`StoreReducerTests`** (drive the `@MainActor` store with `MockGitProvider`):
  - toggleStage moves a file between staged/unstaged and updates `canCommit`;
  - commit clears staged + message, bumps ahead, reselects;
  - confirmDiscard removes the file and clears selection;
  - pop/drop stash mutate the list + reselect;
  - switchBranch updates current branch + reloads;
  - sync sets/clears `isBusy` and emits progress→result toasts;
  - provider error → error toast + rolled-back optimistic state.
- **`MockProviderTests`** — fixtures match the documented counts (7 files, 6 commits, 2 stashes) and
  diffs build without throwing.

Snapshot/preview parity is checked by hand against `reference/Git Workbench Prototype.html` (and the
screenshots, if included).

---

## 5.8 Definition of done (recap)

See [README §5 Acceptance criteria](README.md). In short: `swift build`/`swift test` green, all
three views fully interactive against the mock, visuals within ±1px and exact colors, light+dark,
VoiceOver + shortcuts, and a runnable `GitWorkbenchDemo`.
