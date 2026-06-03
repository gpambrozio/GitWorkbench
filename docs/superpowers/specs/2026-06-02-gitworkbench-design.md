# GitWorkbench — Implementation Design (Core UI Package + Real Git Provider)

- **Date:** 2026-06-02
- **Status:** Design approved; pending written-spec review
- **Extends:** `docs/design_handoff/` — the authoritative, high-fidelity UI handoff. This spec does
  **not** restate that handoff; it records the decisions and the *net-new* design (repo shape, the
  real git provider, testing, and the integrated build plan) that the handoff leaves open.

---

## 1. Overview & scope

We are building two things in one repository:

1. **`GitWorkbench`** — the reusable SwiftUI component exactly as the handoff specifies: a three-pane
   git UI (Changes / History / Stash) driven by a `@MainActor` store, fed entirely through provider
   protocols, with a bundled in-memory mock. **Zero external dependencies.**
2. **`GitWorkbenchGitKit`** — a separate package that implements those provider protocols against a
   **real repository** by shelling out to the system `git`, plus a live demo app that hosts the
   component on an actual repo.

The core package never gains a dependency; the provider package is where real git lives. The
provider protocols (`GitWorkbenchProvider = GitWorkbenchDataSource + GitWorkbenchActionHandler`) are
the seam between them — no additional abstraction is introduced.

## 2. Decisions & rationale

| Decision | Choice | Why |
|---|---|---|
| Scope | Core UI package **+** real git provider | The component alone runs only on mock data; a real provider makes it usable and demonstrable. |
| Git backend | Shell out to `git` CLI via `apple/swift-subprocess` | Most reliable path: transport, credentials (keychain/SSH), hooks, config, LFS all "just work"; trivial SPM dep, no native build/linking; git's porcelain output is machine-stable. Industry-default for new Mac GUIs (Fork, Sourcetree-system, lazygit, jj). |
| Min target | macOS **15+**, Swift 6 toolchain + language mode | Matches the README's stated target; resolves the handoff's internal inconsistency (sample `Package.swift` said 14/5.9); newest SwiftUI APIs; `swift-subprocess` needs a Swift 6.1+ toolchain. |
| Repo shape | **Two packages, one repo** | Keeps the core's dependency graph empty for consumers (acceptance criterion #1). A single multi-target package would force `swift-subprocess` into every consumer's `Package.resolved` via transitive resolution. |
| Store type | `ObservableObject` + `@Published` (not `@Observable`) | Preserves the documented public API in `01-architecture.md` exactly. |

## 3. Git data-access research (condensed)

Full cited survey available on request; the conclusions that drove the backend decision:

- **No production-grade pure-Swift git exists.** Every serious option is a libgit2 wrapper. Ruled out.
- **The well-known `SwiftGit2` is a dead end:** no SPM support and **no push / no stash** in its API
  (both are hard requirements). Its reputation predates SPM.
- **The only modern, SPM-native, Swift-6-aware libgit2 binding is `SwiftGitX`** (ibrahimcetin, MIT,
  v0.4.0 Dec 2025) — it ships typed `Diff`/`Patch` models that map cleanly to the diff UI, but it is
  pre-1.0, vendors a native libgit2, and libgit2's historic weak spot (push / SSH / credentials)
  would need vetting.
- **Shelling out wins on reliability and simplicity for this use case.** The pragmatic process
  wrapper is **`apple/swift-subprocess`** (Apache-2.0, async-native, the toolchain's future
  standard). We parse stable porcelain output; transport delegates to the user's real `git`.
- SwiftGitX remains a viable *alternative backend* a host could write later against the same
  protocols — documented, not built.

## 4. Repository & package layout

The core package is the **repo root**, so the SPM URL resolves directly to the dependency-free
component. The provider is a nested package that path-depends on the root.

```
GitWorkbench/                          ← PACKAGE 1 (repo root): core UI, zero deps
├── Package.swift                      swift-tools 6.0, .macOS(.v15), no dependencies
├── README.md
├── .gitignore
├── Sources/
│   ├── GitWorkbench/                  the library — the handoff's layout (handoff §1.1)
│   └── GitWorkbenchDemo/              mock-backed executable (acceptance criterion #9)
├── Tests/GitWorkbenchTests/          DiffSplitterTests, StoreReducerTests, MockProviderTests
├── docs/
│   ├── design_handoff/               (existing — authoritative UI reference)
│   └── superpowers/specs/            (this document)
│
└── GitWorkbenchGitKit/               ← PACKAGE 2: real git provider
    ├── Package.swift                  deps: .package(path: ".."), apple/swift-subprocess
    ├── Sources/
    │   ├── GitWorkbenchGitKit/        CLIGitProvider, GitRunner, parsers, GitError
    │   └── GitWorkbenchLiveDemo/      executable that opens a real repo
    └── Tests/GitWorkbenchGitKitTests/ parser tests against captured git output
```

- `swift build` / `swift test` at the root builds **only** the clean core.
- `cd GitWorkbenchGitKit && swift build` builds the provider + live demo (path-resolves the root
  package, fetches `swift-subprocess`).
- `GitWorkbenchGitKit` is a working name and may be renamed (e.g. `GitWorkbenchCLI`).

## 5. Core package (`GitWorkbench`) — follow the handoff, with two deltas

The handoff (`docs/design_handoff/01–05` + `reference/src/*`) is implemented **as written**: the
model types (`02`), the views and diff renderer (`03`), the design tokens (`04`), the store /
provider protocols / mock (`01`), and the interactions, a11y, shortcuts, and tests (`05`). The mock
provider mirrors `reference/src/gitdata.js` exactly (repo `aurora-cli`, 7 files, 6 commits, 2
stashes).

Two deltas only, both from §2:

1. **`Package.swift`:** `swift-tools-version: 6.0`, `platforms: [.macOS(.v15)]`, Swift 6 language
   mode, **no dependencies**. (Overrides the handoff's illustrative 5.9 / `.v14` sample.)
2. **Store:** remains `ObservableObject` + `@Published public private(set) var state` as documented.

## 6. Provider package (`GitWorkbenchGitKit`) — design

### 6.1 `CLIGitProvider` & `GitRunner`

`CLIGitProvider` is a `Sendable final class` conforming to `GitWorkbenchProvider`. It holds only
immutable config (the repo `URL` and a resolved `git` executable path), so it carries no mutable
state and needs no actor. Every protocol method runs one or more `git` subprocesses off the main
actor and maps the output into the handoff's model types.

`GitRunner` is a thin `Sendable` wrapper over `apple/swift-subprocess`:

```
struct GitRunner: Sendable {
    let repositoryURL: URL
    let gitExecutable: URL          // resolved once: /usr/bin/git or `xcrun -f git` or PATH lookup
    func run(_ args: [String]) async throws -> GitOutput   // stdout Data, stderr String, exit code
}
```

- Working directory is the repo root; we pass NUL-delimited (`-z`) formats and read stdout as `Data`
  to stay binary-/filename-safe.
- Non-zero exit → throw `GitError` carrying stderr (see §6.4).
- The `git` path is resolved once at provider init; if `git` is missing, init throws a clear error.

### 6.2 Protocol method → git command

**DataSource:**

| Method | Command(s) | Notes |
|---|---|---|
| `loadStatus` | `git status --porcelain=v2 -z --branch` + `git diff --numstat -z` + `git diff --numstat -z --staged` | Branch header lines give `currentBranch`, `upstream`, `ahead`/`behind`. numstat passes supply per-file +/− counts. `repositoryName` = basename of `git rev-parse --show-toplevel` (fallback: parsed `origin` URL). `Author` from `git config user.name`/`user.email`. |
| `loadHistory(before, limit)` | one `git log [<before>^] --max-count=<limit> --numstat --name-status -z --pretty=<fields>` | Commits **and** their files in a single pass. `%P` → `parents` (graph). `%D` → `refs` (`CommitRef`). `%an/%ae` → name/initials; `%aI` → dates (display + relative computed in the parser). Paging continues from `<before>^`. |
| `loadStashes` | `git stash list --pretty=<fields>` then per-stash `git stash show --numstat --name-status -z stash@{n}` | Few stashes → eager file loading is fine. |
| `loadBranches` | `git for-each-ref --format=<fields> refs/heads` | `%(refname:short)`, `%(upstream:short)`, `%(HEAD)` → `isCurrent`. |
| `loadDiff(req)` | working: `git diff [--staged] -- <path>` · commit: `git show <id> -- <path>` · stash: `git stash show -p stash@{n} -- <path>` | Untracked files: synthesize an all-addition `FileDiff` from file contents (or `git diff --no-index /dev/null <path>`). |

**ActionHandler:**

| Method | Command(s) | Notes |
|---|---|---|
| `stage` | `git add -- <paths>` | Works for untracked too. |
| `unstage` | `git restore --staged -- <paths>` | |
| `discard` | tracked: `git restore -- <path>` · untracked: delete file (FileManager) | Irreversible — gated by the UI confirm. |
| `commit` | `git commit -m <message>` → `git log -1 --pretty=<fields>` | Returns the new `Commit`. |
| `pull` / `push` / `fetch` | `git pull` / `git push` / `git fetch` → re-query `git status -b --porcelain=v2` | Build `SyncResult` (ahead/behind + message). Map rejected/non-fast-forward (see §6.4). |
| `switchBranch` | `git switch <name>` | |
| `applyStash` / `popStash` / `dropStash` | `git stash apply` / `pop` / `drop stash@{n}` | |

### 6.3 Parsers (pure, unit-testable)

Each is a pure function from captured git output to model types — no process, no repo, fully
deterministic in tests.

- **`StatusParser`** — porcelain v2: `1` (ordinary), `2` (rename/copy, old→new path), `?`
  (untracked → `.untracked`), `u` (unmerged → `.conflicted`), and `#` branch headers
  (`branch.head`, `branch.upstream`, `branch.ab +A -B`). The XY columns map to staged (X) and
  unstaged (Y) status. **Both-modified files** (X≠`.` *and* Y≠`.`) are emitted as **two**
  `FileChange`s — one staged, one unstaged — with suffixed ids (`"<path>:staged"` /
  `"<path>:unstaged"`) so `Identifiable` stays unique and the file shows in both groups, matching
  how mainstream GUIs present it. (Design note — see §10.)
- **`DiffParser`** — unified `git diff` text → `FileDiff`/`DiffHunk`/`DiffLine`. Splits on `@@`
  headers, walks `+`/`-`/space lines assigning `oldNumber`/`newNumber`, strips the prefix into
  `text`. Detects `Binary files … differ` → `isBinary`. Recognises deleted-file diffs. Mirrors the
  handoff's `hunk()` semantics but over real diff output.
- **`LogParser`** — field-/record-delimited `git log` (e.g. `%x1f` field, `%x1e` record, `-z`) plus
  the trailing `--numstat --name-status` block per commit → `[Commit]` with files, parents, refs,
  and computed initials/relative dates.
- **`RefParser`** — `for-each-ref` lines → `[Branch]`.
- **`StashParser`** — `stash list` + `stash show` → `[Stash]` with files.

### 6.4 Error mapping

`GitError: LocalizedError` wraps a failed command (args + exit code + stderr). `errorDescription`
prefers friendly mappings over raw stderr where detectable:

- push rejected / non-fast-forward → **"Push rejected — pull first"** (matches handoff §1.3 / §5.1).
- not a git repository, no upstream configured, merge conflicts, etc. → concise messages.
- otherwise → trimmed stderr.

The store already turns any thrown error into a red error toast, so the provider's job is only to
throw good `LocalizedError`s.

### 6.5 Live demo app (`GitWorkbenchLiveDemo`)

Minimal SwiftUI macOS app:

- On launch, an `NSOpenPanel` folder picker chooses a repo (validated via
  `git rev-parse --is-inside-work-tree`); the last choice is remembered in `UserDefaults`.
- Builds `CLIGitProvider(repositoryURL:)` → `GitWorkbenchStore(provider:)` → `GitWorkbenchView`, with
  `.task { await store.reload() }`.
- Non-sandboxed for simplicity (plain filesystem path); great for dogfooding on this repo.

## 7. Testing strategy

- **Core (`GitWorkbenchTests`)** — exactly the handoff's `05 §5.7`: `DiffSplitterTests`,
  `StoreReducerTests` (driving the `@MainActor` store with the mock), `MockProviderTests`.
- **Provider parsers (`GitWorkbenchGitKitTests`)** — **primary coverage**: feed each parser
  **captured real git output** (string/`Data` fixtures committed alongside the tests) and assert the
  resulting models. Covers status (incl. renames, untracked, conflicts, both-modified), unified diffs
  (add-only, delete-only, interleaved, binary, deleted file), log (parents, refs, multi-file),
  branches, and stashes. Fast, deterministic, no git required.
- **Optional integration smoke tests** — create a temp repo in `setUp` (`git init`, a couple of
  commits, a stash), run `CLIGitProvider` end-to-end, and skip gracefully if `git` is unavailable on
  the test host.

## 8. Build plan

Core first (the provider depends on stable Model + Provider protocols), then GitKit. Each phase stays
green (compiles + previews/tests) before the next.

**Core — exactly the handoff's P0–P9** (`README §6`): P0 scaffold → P1 design system → P2 diff
renderer → P3 Changes → P4 History → P5 Stash → P6 store & provider/mock → P7 a11y & keys → P8 demo &
tests → P9 polish.

**GitKit:**

- **G1 — Scaffold:** second package + `Package.swift` (path-dep on root + `swift-subprocess`);
  `GitRunner`, `GitError`, a `CLIGitProvider` whose methods are stubbed/`throw notImplemented`.
- **G2 — Read side:** the five parsers + their fixture tests; wire all `DataSource` methods. After
  G2, the live demo can already *display* a real repo read-only.
- **G3 — Write side:** stage / unstage / discard / commit / pull / push / fetch / switchBranch /
  stash apply-pop-drop, with error mapping; optional integration smoke tests.
- **G4 — Live demo:** folder-picker app hosting the component against a real repo; manual
  verification of every interaction end-to-end.

(Parsers in G2 depend only on the model types from core P2/P6, so GitKit read-side work can begin as
soon as those types exist if parallelization is wanted.)

## 9. Acceptance criteria

The handoff's `README §5` (1–9) in full, **plus**:

10. The root package builds and tests with **zero external dependencies**; consuming it resolves
    nothing extra.
11. `GitWorkbenchGitKit` builds; `CLIGitProvider` satisfies `GitWorkbenchProvider`; parser tests pass
    against captured fixtures.
12. `GitWorkbenchLiveDemo` opens a chosen real repository and every interaction in
    `05-interactions-a11y.md` works against it (stage/unstage, discard, commit, pull/push/fetch,
    branch switch, history browse, stash apply/pop/drop, unified⇄split).
13. Git failures surface as the existing error toasts via `GitError: LocalizedError` (push-rejected
    mapped).

## 10. Design notes & risks

- **Both-modified files** (staged *and* unstaged changes to the same path): handled by emitting two
  `FileChange`s with suffixed ids (§6.3). This is a small, contained deviation from the handoff's
  "`id` = path" note, chosen for correctness and to match mainstream GUIs. Flagged for awareness.
- **Untracked-file diffs:** git's plumbing doesn't diff untracked files directly; we synthesize an
  all-addition diff. Verify against the renderer's add-only path.
- **`swift-subprocess` is pre-1.0:** minor API churn possible; it's isolated entirely within
  `GitRunner`, so churn can't reach the UI or the provider surface.
- **Large histories/diffs:** `loadHistory` is paged (`--max-count`); the diff renderer is already
  lazy per the handoff. No eager full-history load.
