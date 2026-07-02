# 02 — Data Model

All models are `public`, value-type `struct`s, `Identifiable` where listed, `Hashable`, and
`Sendable`. They mirror the shapes in `reference/src/gitdata.js`. Nothing here knows about git
plumbing — these are presentation models the host maps its real data into.

---

## 2.1 File status

```swift
public enum FileStatus: String, Sendable, CaseIterable {
    case modified   = "M"
    case added      = "A"
    case deleted    = "D"
    case renamed    = "R"
    case untracked  = "U"
    case conflicted = "!"   // merge conflict (see 03 states)

    /// Long label shown in the diff header: "Modified", "Added", …
    public var label: String { … }
}
```

Color per status is defined in [04 §Status colors](04-design-tokens.md), not on the model.

---

## 2.2 File change

One changed file in the working tree, a commit, or a stash.

```swift
public struct FileChange: Identifiable, Hashable, Sendable {
    public var id: String          // stable key; use the repo-relative path
    public var path: String        // "src/commands/sync.ts"
    public var directory: String   // "src/commands"  ("" for root)
    public var name: String        // "sync.ts"
    public var status: FileStatus
    public var isStaged: Bool       // only meaningful in working-tree context
    public var additions: Int       // "+24"
    public var deletions: Int       // "−6"
}
```

Convenience: derive `directory`/`name` from `path` in an initializer (see `cf()` in
`reference/src/gitdata.js`).

---

## 2.3 Diff

A file's diff is a list of **hunks**; each hunk is a list of **lines**. This is the unified form;
the split renderer derives two columns from it (see `splitRows` in `reference/src/diff.jsx`).

```swift
public struct FileDiff: Sendable, Hashable {
    public var file: FileChange
    public var hunks: [DiffHunk]
    public var isBinary: Bool = false   // if true, render a before→after metadata row
}

public struct DiffHunk: Identifiable, Sendable, Hashable {
    public var id = UUID()
    public var header: String           // "@@ -14,8 +14,9 @@"
    public var lines: [DiffLine]
}

public struct DiffLine: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable { case context, addition, deletion }
    public var id = UUID()
    public var kind: Kind
    public var oldNumber: Int?          // line no. in old file (nil for additions)
    public var newNumber: Int?          // line no. in new file (nil for deletions)
    public var text: String             // raw line content WITHOUT the +/-/space prefix
}
```

### Building hunks (port of `hunk()` in gitdata.js)
Given a hunk's old/new start line and an array of prefixed raw lines (`"+…"`, `"-…"`, `" …"`),
walk the lines assigning `oldNumber`/`newNumber`:
- `context`: both numbers advance.
- `addition`: only `newNumber` advances; `oldNumber == nil`.
- `deletion`: only `oldNumber` advances; `newNumber == nil`.

Provide a test (`DiffSplitterTests`) covering: a pure-add file, a pure-delete file, and an
interleaved hunk, verifying both unified ordering and the split pairing.

### Split derivation
For the split view, walk the hunk's lines accumulating runs of deletions (left) and additions
(right); on each `context` line, flush the run by zipping deletions↔additions into rows (padding the
shorter side with empty cells), then emit the context line on both sides. See `splitRows` for the
exact algorithm — match it.

---

## 2.4 Commit

```swift
public struct Commit: Identifiable, Sendable, Hashable {
    public var id: String           // full SHA
    public var shortSHA: String     // "9f2c1a4"
    public var summary: String      // first line of the message
    public var body: String         // remainder (may be empty)
    public var authorName: String
    public var authorEmail: String
    public var authorInitials: String   // "GA" — for the monogram avatar
    public var date: String         // display string, e.g. "Today, 09:42"
    public var relativeDate: String // "3 hours ago"
    public var refs: [CommitRef]    // HEAD / branch / tag pills shown on the row
    public var parents: [String]    // parent short SHAs
    public var files: [FileChange]  // files changed in this commit
}

public enum CommitRef: Sendable, Hashable {
    case head                 // "HEAD" pill (accent)
    case branch(String)       // branch pill (blue) with branch glyph
    case tag(String)          // tag pill (green) with tag glyph
}
```

> In the prototype, refs are plain strings (`["HEAD","feat/auto-sync","v0.5.0-rc.1"]`) and the pill
> style is inferred (`TagPill`). Prefer the typed `CommitRef` here so styling is explicit, but the
> visual result must match `TagPill` in `reference/src/proto-views.jsx`.

---

## 2.5 Stash

```swift
public struct Stash: Identifiable, Sendable, Hashable {
    public var id: String          // stable key
    public var ref: String         // "stash@{0}"
    public var message: String     // "WIP: tune retry delays"
    public var branch: String      // branch it was created on
    public var date: String        // "Today, 12:05"
    public var relativeDate: String// "40 minutes ago"
    public var files: [FileChange]
}
```

---

## 2.6 Branch & repository status

```swift
public struct Branch: Identifiable, Sendable, Hashable {
    public var id: String          // branch name
    public var name: String        // "feat/auto-sync"
    public var isCurrent: Bool
    public var upstream: String?   // "origin/feat/auto-sync"
    public var ahead: Int          // commits ahead of upstream (to push); 0 when in sync/untracked
    public var behind: Int         // commits behind upstream (to pull); 0 when in sync/untracked
}

public struct RepositoryStatus: Sendable {
    public var repositoryName: String   // "aurora-cli"
    public var currentBranch: String    // "feat/auto-sync"
    public var upstream: String?        // "origin/feat/auto-sync"
    public var ahead: Int               // commits to push
    public var behind: Int              // commits to pull
    public var files: [FileChange]      // all changed files (staged flag set per file)
    public var author: Author           // current user, for the composer avatar
}

public struct Author: Sendable, Hashable {
    public var name: String
    public var initials: String
}
```

Derived collections (compute in the store, not the model):
`staged = files.filter(\.isStaged)`, `unstaged = files.filter { !$0.isStaged }`.

---

## 2.7 UI state snapshot

Held by the store; the entire view tree is a function of it.

```swift
public struct WorkbenchState: Sendable {
    public var activeView: WorkspaceView = .changes
    public var diffMode: DiffMode = .split

    // repo status
    public var repo: RepositoryStatus
    public var branches: [Branch] = []

    // changes view
    public var selectedFileID: FileChange.ID?
    public var commitMessage: String = ""
    public var pendingDiscard: FileChange?     // non-nil → confirm popover up

    // history view
    public var commits: [Commit] = []
    public var selectedCommitID: Commit.ID?
    public var selectedCommitFileID: FileChange.ID?

    // stash view
    public var stashes: [Stash] = []
    public var selectedStashID: Stash.ID?
    public var selectedStashFileID: FileChange.ID?

    // diff cache for the currently shown file (keyed by request)
    public var currentDiff: FileDiff?

    // transient
    public var isBusy: Bool = false            // a sync is in flight
    public var toast: Toast?
    public var branchMenuOpen: Bool = false

    // derived
    public var staged: [FileChange] { repo.files.filter(\.isStaged) }
    public var unstaged: [FileChange] { repo.files.filter { !$0.isStaged } }
    public var canCommit: Bool { !staged.isEmpty && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
```

---

## 2.8 Toast

```swift
public struct Toast: Identifiable, Sendable, Equatable {
    public enum Style: Sendable { case success, info, error, progress }
    public var id = UUID()
    public var message: String
    public var style: Style = .success
}
```

Toast presentation/animation in [03 §Toast](03-views.md); auto-dismiss timing in
[05 §Toasts](05-interactions-a11y.md).

---

## 2.9 Fixtures (mock data)

Recreate `reference/src/gitdata.js` as Swift fixtures in `MockGitProvider` (or a `Fixtures` enum).
Match it exactly so previews look identical to the prototype:

- **Repo:** `aurora-cli`, branch `feat/auto-sync`, upstream `origin/feat/auto-sync`, ahead 2,
  behind 1, author Gustavo / `GA`.
- **7 changed files:** `sync.ts` (M, staged, +24/−6, 2 hunks), `index.ts` (M, staged, +8/−2),
  `logger.ts` (A, staged, +31), `package.json` (M, +3/−1), `README.md` (M, +5), `poller.ts`
  (D, −18), `.env.example` (U, +4). Use the exact hunks in `gitdata.js`.
- **6 commits:** SHAs `9f2c1a4` (HEAD + branch), `3b8e7d2`, `a17f9c0` (tag `v0.5.0-rc.1`),
  `e4d5b61`, `77ac3f9`, `1c0aa28` (branch `main`). Authors Gustavo (`GA`, hue 295) and Mira Patel
  (`MP`, hue 25). Files + hunks per `gitdata.js`.
- **2 stashes:** `stash@{0}` "WIP: tune retry delays" (1 file), `stash@{1}` "experiment: parallel
  push to mirrors" (2 files).
- **Branches:** `main`, `develop`, `feat/auto-sync` (current), `fix/log-levels`.

Read `gitdata.js` directly for the literal hunk contents — copy them verbatim.
