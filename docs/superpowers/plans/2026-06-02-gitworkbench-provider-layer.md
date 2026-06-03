# GitWorkbench Provider Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the host-integration provider protocols, a compact-patch → `FileDiff` builder, the diff fixtures (ported from the prototype), and a complete in-memory `MockGitProvider` that returns all data and performs all actions — fully unit-tested, with no UI or store changes.

**Architecture:** This is Plan 2 of the GitWorkbench program (foundation merged in Plan 1). It builds the **data/provider seam** the store will consume next (Plan 3). The provider is `Sendable`; `MockGitProvider` is an `actor` holding mutable in-memory repo state so its action methods can mutate safely off the main actor. Diffs are built from the same compact-patch representation the prototype uses (`reference/src/gitdata.js`'s `hunk()`), so visual parity is preserved when the renderer lands later. Nothing here touches `GitWorkbenchView` or introduces a store.

**Tech Stack:** Swift 6 (language mode), SwiftPM, macOS 15+, XCTest. No third-party dependencies. Builds on the Plan 1 model/theme/fixture layer already on `main`.

**Conventions for this plan:**
- All public types `public`, `Sendable`; protocols as specified in `docs/design_handoff/01-architecture.md §1.3`.
- TDD for logic (the diff builder, the mock's action mutations); build-verify for pure protocol/data declarations.
- Diff hunk **content** is the authoritative `reference/src/gitdata.js`; where this plan says "port verbatim from gitdata.js," reproduce those exact lines (do not paraphrase) — they are the source of truth for later visual parity, and duplicating ~200 lines of patch text into this plan would be error-prone.
- Run every command from the repo root (`/Users/gustavoambrozio/Development/GitWorkbench`). Current branch for execution is a fresh feature branch off `main`.

---

### Task 1: Provider protocols

**Files:**
- Create: `Sources/GitWorkbench/Provider/GitWorkbenchProvider.swift`

> Pure protocol/type declarations (the host-integration seam from `01-architecture.md §1.3`). Build-verified; no behavior to unit-test.

- [ ] **Step 1: Write the protocols and request/result types**

`Sources/GitWorkbench/Provider/GitWorkbenchProvider.swift`:

```swift
import Foundation

/// The full host integration surface: a data source plus an action handler.
public protocol GitWorkbenchProvider: GitWorkbenchDataSource, GitWorkbenchActionHandler {}

/// Reads repository state. All methods run off the main actor; the provider is `Sendable`.
public protocol GitWorkbenchDataSource: Sendable {
    /// Working-tree status: branch, ahead/behind, staged + unstaged files.
    func loadStatus() async throws -> RepositoryStatus
    /// Commit history for the current branch (newest first). `before` pages older than that commit.
    func loadHistory(before: Commit.ID?, limit: Int) async throws -> [Commit]
    /// Stash entries (index 0 newest).
    func loadStashes() async throws -> [Stash]
    /// Local branches for the switcher.
    func loadBranches() async throws -> [Branch]
    /// The diff for one file in a given context (working tree, a commit, or a stash).
    func loadDiff(_ request: DiffRequest) async throws -> FileDiff
}

/// Performs git operations on behalf of the UI.
public protocol GitWorkbenchActionHandler: Sendable {
    func stage(_ files: [FileChange]) async throws
    func unstage(_ files: [FileChange]) async throws
    func discard(_ file: FileChange) async throws
    func commit(message: String, staged: [FileChange]) async throws -> Commit

    func pull() async throws -> SyncResult
    func push() async throws -> SyncResult
    func fetch() async throws -> SyncResult
    func switchBranch(to branch: Branch) async throws

    func applyStash(_ stash: Stash) async throws
    func popStash(_ stash: Stash) async throws
    func dropStash(_ stash: Stash) async throws
}

/// Identifies which diff to load.
public struct DiffRequest: Sendable {
    public enum Context: Sendable {
        case workingTree(staged: Bool)
        case commit(Commit.ID)
        case stash(Stash.ID)
    }
    public var file: FileChange
    public var context: Context
    public var mode: DiffMode   // a hint; the renderer can re-derive split from unified

    public init(file: FileChange, context: Context, mode: DiffMode) {
        self.file = file
        self.context = context
        self.mode = mode
    }
}

/// The result of a pull/push/fetch.
public struct SyncResult: Sendable {
    public var ahead: Int
    public var behind: Int
    public var message: String   // e.g. "Pushed 2 commits to origin"

    public init(ahead: Int, behind: Int, message: String) {
        self.ahead = ahead
        self.behind = behind
        self.message = message
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/GitWorkbench/Provider/GitWorkbenchProvider.swift
git commit -m "Provider: add GitWorkbenchProvider protocols, DiffRequest, SyncResult"
```

---

### Task 2: DiffBuilder (compact-patch → DiffHunk)

**Files:**
- Create: `Sources/GitWorkbench/Model/DiffBuilder.swift`
- Test: `Tests/GitWorkbenchTests/DiffBuilderTests.swift`

> A direct port of `hunk()` in `reference/src/gitdata.js`: given a hunk's old/new start line and an array of prefixed raw lines (`"+…"`, `"-…"`, `" …"`), assign `oldNumber`/`newNumber` and synthesize the `@@` header. This is the unified-form half of the handoff's diff work; the split derivation comes with the renderer (later plan).

- [ ] **Step 1: Write the failing test**

`Tests/GitWorkbenchTests/DiffBuilderTests.swift`:

```swift
import XCTest
@testable import GitWorkbench

final class DiffBuilderTests: XCTestCase {
    func test_interleavedHunkAssignsNumbersAndHeader() {
        let h = DiffBuilder.hunk(oldStart: 14, newStart: 14, [
            " context",
            "-removed",
            "+added",
            " context2",
        ])
        XCTAssertEqual(h.lines.map(\.kind), [.context, .deletion, .addition, .context])
        XCTAssertEqual(h.lines.map(\.oldNumber), [14, 15, nil, 16])
        XCTAssertEqual(h.lines.map(\.newNumber), [14, nil, 15, 16])
        XCTAssertEqual(h.lines.map(\.text), ["context", "removed", "added", "context2"])
        // old count = context+deletion = 3; new count = context+addition = 3
        XCTAssertEqual(h.header, "@@ -14,3 +14,3 @@")
    }

    func test_pureAddHunk() {
        let h = DiffBuilder.hunk(oldStart: 0, newStart: 1, ["+a", "+b", "+c"])
        XCTAssertEqual(h.lines.map(\.kind), [.addition, .addition, .addition])
        XCTAssertEqual(h.lines.map(\.oldNumber), [nil, nil, nil])
        XCTAssertEqual(h.lines.map(\.newNumber), [1, 2, 3])
        // old count = 0; new count = 3
        XCTAssertEqual(h.header, "@@ -0,0 +1,3 @@")
    }

    func test_pureDeleteHunk() {
        let h = DiffBuilder.hunk(oldStart: 1, newStart: 0, ["-x", "-y"])
        XCTAssertEqual(h.lines.map(\.kind), [.deletion, .deletion])
        XCTAssertEqual(h.lines.map(\.oldNumber), [1, 2])
        XCTAssertEqual(h.lines.map(\.newNumber), [nil, nil])
        XCTAssertEqual(h.header, "@@ -1,2 +0,0 @@")
    }

    func test_emptyPrefixedLinesKeepEmptyText() {
        let h = DiffBuilder.hunk(oldStart: 1, newStart: 1, [" ", "+", "-"])
        XCTAssertEqual(h.lines.map(\.text), ["", "", ""])
        XCTAssertEqual(h.lines.map(\.kind), [.context, .addition, .deletion])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DiffBuilderTests`
Expected: FAIL — `DiffBuilder` undefined.

- [ ] **Step 3: Write the implementation**

`Sources/GitWorkbench/Model/DiffBuilder.swift`:

```swift
import Foundation

/// Builds `DiffHunk`/`FileDiff` values from a compact patch representation.
/// Port of `hunk()` in reference/src/gitdata.js.
public enum DiffBuilder {
    /// Each raw line is prefixed with `+` (addition), `-` (deletion), or a space (context).
    /// The prefix is stripped into `text`; line numbers advance per the prototype's rules.
    public static func hunk(oldStart: Int, newStart: Int, _ raw: [String]) -> DiffHunk {
        var oldNo = oldStart
        var newNo = newStart
        var lines: [DiffLine] = []
        lines.reserveCapacity(raw.count)

        for line in raw {
            let prefix = line.first
            let text = String(line.dropFirst())
            switch prefix {
            case "+":
                lines.append(DiffLine(kind: .addition, oldNumber: nil, newNumber: newNo, text: text))
                newNo += 1
            case "-":
                lines.append(DiffLine(kind: .deletion, oldNumber: oldNo, newNumber: nil, text: text))
                oldNo += 1
            default: // space or empty → context
                lines.append(DiffLine(kind: .context, oldNumber: oldNo, newNumber: newNo, text: text))
                oldNo += 1
                newNo += 1
            }
        }

        let oldCount = lines.lazy.filter { $0.kind != .addition }.count
        let newCount = lines.lazy.filter { $0.kind != .deletion }.count
        let header = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
        return DiffHunk(header: header, lines: lines)
    }

    /// Convenience to assemble a `FileDiff` from a file and its hunks.
    public static func fileDiff(_ file: FileChange, hunks: [DiffHunk], isBinary: Bool = false) -> FileDiff {
        FileDiff(file: file, hunks: hunks, isBinary: isBinary)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DiffBuilderTests`
Expected: PASS (all four).

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Model/DiffBuilder.swift Tests/GitWorkbenchTests/DiffBuilderTests.swift
git commit -m "Model: add DiffBuilder (compact patch -> DiffHunk) with tests"
```

---

### Task 3: Diff fixtures (ported from gitdata.js)

**Files:**
- Create: `Sources/GitWorkbench/Provider/FixtureDiffs.swift`
- Test: `Tests/GitWorkbenchTests/FixtureDiffsTests.swift`

> The mock provider's `loadDiff` returns these. They mirror the hunks in `reference/src/gitdata.js` exactly (so the eventual renderer matches the prototype). Build them with `DiffBuilder.hunk(...)`. Diffs are keyed by `(context, path)`.

**Reference mapping — read `reference/src/gitdata.js` and port every hunk:**
- In `gitdata.js`, each file/commit-file/stash-file has `hunks: [hunk(oldStart, newStart, [lines])]`. Port each to `DiffBuilder.hunk(oldStart: <o>, newStart: <n>, [<lines>])`, copying each prefixed line **verbatim** as displayed source text (keep the leading `+`/`-`/space). Escaping: `gitdata.js` uses single-quoted JS strings, so inner double-quotes are bare — escape them as `\"` in the Swift double-quoted literal. Where the JS shows a doubled backslash (`\\x1b`, `\\n`), that is ONE literal backslash in the diff text (the diff renders TypeScript *source*, e.g. the literal text `\x1b[90m`) — reproduce it in Swift as a doubled backslash (`\\x1b`, `\\n`); do NOT turn it into a real ESC/newline character. Backticks and `${…}` are literal text — copy as-is. Preserve every line.
- Working-tree files come from the top-level `files` array (7 files; `sync.ts` has 2 hunks, the rest 1 each). `poller.ts` is the deleted file; `.env.example` is untracked.
- Commit diffs come from each commit's `files` (via `cf(path, status, add, del, hunks)`); stash diffs from each stash's `files`.

- [ ] **Step 1: Write the failing test**

`Tests/GitWorkbenchTests/FixtureDiffsTests.swift`:

```swift
import XCTest
@testable import GitWorkbench

final class FixtureDiffsTests: XCTestCase {
    func test_workingTreeDiffForSyncHasTwoHunks() {
        let file = Fixtures.files.first { $0.path == "src/commands/sync.ts" }!
        let diff = FixtureDiffs.diff(for: file, context: .workingTree(staged: true))!
        XCTAssertEqual(diff.hunks.count, 2)
        XCTAssertEqual(diff.file.path, "src/commands/sync.ts")
        XCTAssertFalse(diff.isBinary)
        // first hunk starts at old/new line 14
        XCTAssertTrue(diff.hunks[0].header.hasPrefix("@@ -14,"))
    }

    func test_addedFileDiffIsAllAdditions() {
        let logger = Fixtures.files.first { $0.path == "src/utils/logger.ts" }!
        let diff = FixtureDiffs.diff(for: logger, context: .workingTree(staged: true))!
        let kinds = Set(diff.hunks.flatMap { $0.lines.map(\.kind) })
        XCTAssertEqual(kinds, [.addition])
    }

    func test_deletedFileDiffIsAllDeletions() {
        let poller = Fixtures.files.first { $0.path == "src/legacy/poller.ts" }!
        let diff = FixtureDiffs.diff(for: poller, context: .workingTree(staged: false))!
        let kinds = Set(diff.hunks.flatMap { $0.lines.map(\.kind) })
        XCTAssertEqual(kinds, [.deletion])
    }

    func test_commitDiffResolvesByCommitAndPath() {
        let commit = Fixtures.commits.first { $0.shortSHA == "9f2c1a4" }!
        let file = commit.files.first { $0.path == "src/commands/sync.ts" }!
        let diff = FixtureDiffs.diff(for: file, context: .commit(commit.id))
        XCTAssertNotNil(diff)
        XCTAssertFalse(diff!.hunks.isEmpty)
    }

    func test_stashDiffResolvesByStashAndPath() {
        let stash = Fixtures.stashes[0]
        let file = stash.files[0]
        let diff = FixtureDiffs.diff(for: file, context: .stash(stash.id))
        XCTAssertNotNil(diff)
        XCTAssertFalse(diff!.hunks.isEmpty)
    }

    func test_unknownFileReturnsNil() {
        let ghost = FileChange(path: "does/not/exist.txt", status: .modified)
        XCTAssertNil(FixtureDiffs.diff(for: ghost, context: .workingTree(staged: false)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FixtureDiffsTests`
Expected: FAIL — `FixtureDiffs` undefined.

- [ ] **Step 3: Write the implementation**

Create `Sources/GitWorkbench/Provider/FixtureDiffs.swift`. Structure it exactly as below, filling each hunk by porting verbatim from `gitdata.js`. The worked example for `sync.ts` is shown in full (it is the two-hunk case — copy its lines exactly from `gitdata.js`); reproduce the same pattern for the other working files, the commit files, and the stash files.

```swift
import Foundation

/// Diff content for the mock provider, mirroring reference/src/gitdata.js hunks.
/// Keyed by diff context + repo-relative path.
public enum FixtureDiffs {

    /// Resolve a diff for a file in a context, or nil if there is no fixture for it.
    public static func diff(for file: FileChange, context: DiffRequest.Context) -> FileDiff? {
        let hunks: [DiffHunk]?
        switch context {
        case .workingTree:
            hunks = workingTree[file.path]
        case .commit(let id):
            hunks = commitDiffs[id]?[file.path]
        case .stash(let id):
            hunks = stashDiffs[id]?[file.path]
        }
        guard let hunks else { return nil }
        return DiffBuilder.fileDiff(file, hunks: hunks)
    }

    // MARK: Working-tree diffs (by path) — port all 7 from gitdata.js `files`

    static let workingTree: [String: [DiffHunk]] = [
        "src/commands/sync.ts": [
            DiffBuilder.hunk(oldStart: 14, newStart: 14, [
                " import { Logger } from \"../utils/logger\";",
                " import { loadConfig } from \"../config\";",
                "-import { sleep } from \"../utils/time\";",
                "+import { sleep, jitter } from \"../utils/time\";",
                " ",
                " const MAX_RETRIES = 5;",
                "+const BASE_DELAY_MS = 250;",
                " ",
                " export async function sync(opts: SyncOptions) {",
                "   const cfg = await loadConfig(opts.cwd);",
            ]),
            DiffBuilder.hunk(oldStart: 41, newStart: 42, [
                "   const remote = cfg.remotes[opts.remote ?? \"origin\"];",
                "-  if (!remote) throw new Error(\"unknown remote\");",
                "+  if (!remote) {",
                "+    log.error(`No remote named \"${opts.remote}\"`);",
                "+    throw new SyncError(\"UNKNOWN_REMOTE\", opts.remote);",
                "+  }",
                " ",
                "-  for (let i = 0; i < MAX_RETRIES; i++) {",
                "-    try {",
                "-      return await push(remote, opts.branch);",
                "-    } catch (e) {",
                "-      await sleep(1000);",
                "+  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {",
                "+    try {",
                "+      return await push(remote, opts.branch);",
                "+    } catch (err) {",
                "+      if (!isRetryable(err)) throw err;",
                "+      const delay = BASE_DELAY_MS * 2 ** attempt + jitter(100);",
                "+      log.warn(`push failed (attempt ${attempt}), retrying in ${delay}ms`);",
                "+      await sleep(delay);",
                "     }",
                "   }",
                "+  throw new SyncError(\"EXHAUSTED\", remote.url);",
                " }",
            ]),
        ],
        // PORT the remaining 6 working files verbatim from gitdata.js `files`:
        //   "src/index.ts"           → hunk(3, 3, [...])
        //   "src/utils/logger.ts"    → hunk(0, 1, [...])   (COLORS lines are literal source: JS "\\x1b[90m" is the text \x1b[90m, so write Swift "\\x1b[90m" — a literal backslash, NOT a real ESC char)
        //   "package.json"           → hunk(2, 2, [...])
        //   "README.md"              → hunk(18, 18, [...])
        //   "src/legacy/poller.ts"   → hunk(1, 0, [...])   (deleted file, all "-")
        //   ".env.example"           → hunk(0, 1, [...])
    ]

    // MARK: Commit diffs (by commit id, then path) — port from each commit's `files`

    static let commitDiffs: [String: [String: [DiffHunk]]] = [
        "9f2c1a4e7b3": [
            "src/utils/logger.ts": [DiffBuilder.hunk(oldStart: 0, newStart: 1, [
                "+type Level = \"debug\" | \"info\" | \"warn\" | \"error\";",
                "+export class Logger {",
                "+  constructor(private scope: string) {}",
                "+  info = (m: string) => this.emit(\"info\", m);",
                "+}",
            ])],
            "src/commands/sync.ts": [DiffBuilder.hunk(oldStart: 11, newStart: 11, [
                " import { loadConfig } from \"../config\";",
                "+import { Logger } from \"../utils/logger\";",
                " ",
                "-const log = console;",
                "+const log = new Logger(\"sync\");",
                " ",
            ])],
        ],
        // PORT the remaining 5 commits' files verbatim from gitdata.js `commits[*].files`,
        // keyed by the commit's full sha (e.g. "3b8e7d2f1a9", "a17f9c0b5e2", "e4d5b61c8d4",
        // "77ac3f9d2b6", "1c0aa28f0c1").
    ]

    // MARK: Stash diffs (by stash id, then path) — port from each stash's `files`

    static let stashDiffs: [String: [String: [DiffHunk]]] = [
        "stash0": [
            "src/commands/sync.ts": [DiffBuilder.hunk(oldStart: 38, newStart: 38, [
                "   for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {",
                "-      const delay = BASE_DELAY_MS * 2 ** attempt;",
                "+      const delay = Math.min(BASE_DELAY_MS * 2 ** attempt, 8000);",
                "+      const wobble = jitter(delay * 0.2);",
                "-      await sleep(delay);",
                "+      await sleep(delay + wobble);",
                "   }",
            ])],
        ],
        // PORT stash1's two files verbatim from gitdata.js `stashes[1].files`
        //   ("src/commands/sync.ts" hunk(44,44,[...]) and "src/config.ts" hunk(8,8,[...])).
    ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FixtureDiffsTests`
Expected: PASS (all six). If `test_addedFileDiffIsAllAdditions`/`test_deletedFileDiffIsAllDeletions` fail, a ported hunk has a wrong prefix — recheck against gitdata.js.

- [ ] **Step 5: Build the full suite**

Run: `swift test`
Expected: all prior tests + the new DiffBuilder/FixtureDiffs tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/GitWorkbench/Provider/FixtureDiffs.swift Tests/GitWorkbenchTests/FixtureDiffsTests.swift
git commit -m "Provider: add diff fixtures ported from gitdata.js"
```

---

### Task 4: MockGitProvider — data source (reads)

**Files:**
- Create: `Sources/GitWorkbench/Provider/MockGitProvider.swift`
- Test: `Tests/GitWorkbenchTests/MockProviderTests.swift`

> An `actor` holding mutable in-memory repo state, seeded from `Fixtures`. This task implements the `GitWorkbenchDataSource` reads + the actor's stored state; Task 5 adds the `GitWorkbenchActionHandler` mutations. Small `Task.sleep` delays make in-flight states demonstrable; tests inject a zero delay for speed.

- [ ] **Step 1: Write the failing test**

`Tests/GitWorkbenchTests/MockProviderTests.swift`:

```swift
import XCTest
@testable import GitWorkbench

final class MockProviderTests: XCTestCase {
    private func provider() -> MockGitProvider { MockGitProvider(delay: .zero) }

    func test_loadStatusReturnsSeededRepo() async throws {
        let status = try await provider().loadStatus()
        XCTAssertEqual(status.repositoryName, "aurora-cli")
        XCTAssertEqual(status.files.count, 7)
        XCTAssertEqual(status.ahead, 2)
        XCTAssertEqual(status.behind, 1)
    }

    func test_loadHistoryRespectsLimitAndPaging() async throws {
        let p = provider()
        let firstTwo = try await p.loadHistory(before: nil, limit: 2)
        XCTAssertEqual(firstTwo.map(\.shortSHA), ["9f2c1a4", "3b8e7d2"])
        // page older than the 2nd commit
        let next = try await p.loadHistory(before: firstTwo[1].id, limit: 2)
        XCTAssertEqual(next.map(\.shortSHA), ["a17f9c0", "e4d5b61"])
    }

    func test_loadStashesAndBranches() async throws {
        let p = provider()
        let stashes = try await p.loadStashes()
        XCTAssertEqual(stashes.map(\.ref), ["stash@{0}", "stash@{1}"])
        let branches = try await p.loadBranches()
        XCTAssertEqual(branches.first(where: \.isCurrent)?.name, "feat/auto-sync")
    }

    func test_loadDiffWorkingTreeAndUnknown() async throws {
        let p = provider()
        let sync = Fixtures.files.first { $0.path == "src/commands/sync.ts" }!
        let diff = try await p.loadDiff(DiffRequest(file: sync, context: .workingTree(staged: true), mode: .split))
        XCTAssertEqual(diff.hunks.count, 2)

        let ghost = FileChange(path: "nope.txt", status: .modified)
        do {
            _ = try await p.loadDiff(DiffRequest(file: ghost, context: .workingTree(staged: false), mode: .unified))
            XCTFail("expected an error for a missing diff")
        } catch let error as MockGitError {
            XCTAssertEqual(error, .noDiff("nope.txt"))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MockProviderTests`
Expected: FAIL — `MockGitProvider` / `MockGitError` undefined.

- [ ] **Step 3: Write the implementation (data-source half + state)**

`Sources/GitWorkbench/Provider/MockGitProvider.swift`:

```swift
import Foundation

/// Errors surfaced by the in-memory mock.
public enum MockGitError: Error, LocalizedError, Equatable {
    case noDiff(String)

    public var errorDescription: String? {
        switch self {
        case .noDiff(let path): return "No diff available for \(path)."
        }
    }
}

/// In-memory `GitWorkbenchProvider` backed by `Fixtures`. Mutates its own copy so the
/// demo/preview/tests can exercise every action. `actor`-isolated for safe mutation.
public actor MockGitProvider: GitWorkbenchProvider {
    private var status: RepositoryStatus
    private var commits: [Commit]
    private var stashes: [Stash]
    private var branches: [Branch]
    private let delay: Duration

    /// `delay` is the artificial latency per call (default 700ms; pass `.zero` in tests).
    public init(delay: Duration = .milliseconds(700)) {
        self.status = Fixtures.repositoryStatus
        self.commits = Fixtures.commits
        self.stashes = Fixtures.stashes
        self.branches = Fixtures.branches
        self.delay = delay
    }

    private func pause() async {
        if delay != .zero { try? await Task.sleep(for: delay) }
    }

    // MARK: GitWorkbenchDataSource

    public func loadStatus() async throws -> RepositoryStatus {
        await pause()
        return status
    }

    public func loadHistory(before: Commit.ID?, limit: Int) async throws -> [Commit] {
        await pause()
        let start: Int
        if let before, let idx = commits.firstIndex(where: { $0.id == before }) {
            start = idx + 1
        } else {
            start = 0
        }
        guard start < commits.count else { return [] }
        return Array(commits[start..<min(start + limit, commits.count)])
    }

    public func loadStashes() async throws -> [Stash] {
        await pause()
        return stashes
    }

    public func loadBranches() async throws -> [Branch] {
        await pause()
        return branches
    }

    public func loadDiff(_ request: DiffRequest) async throws -> FileDiff {
        await pause()
        guard let diff = FixtureDiffs.diff(for: request.file, context: request.context) else {
            throw MockGitError.noDiff(request.file.path)
        }
        return diff
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MockProviderTests`
Expected: PASS (all four).

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Provider/MockGitProvider.swift Tests/GitWorkbenchTests/MockProviderTests.swift
git commit -m "Provider: add MockGitProvider data source (actor, seeded from fixtures)"
```

---

### Task 5: MockGitProvider — action handler (mutations)

**Files:**
- Modify: `Sources/GitWorkbench/Provider/MockGitProvider.swift` (add the `GitWorkbenchActionHandler` methods in an extension)
- Modify: `Tests/GitWorkbenchTests/MockProviderTests.swift` (add action tests)

> Actions mutate the actor's in-memory state so repeated reads reflect them. Behavior mirrors the handoff: stage/unstage flip `isStaged`; discard removes the file; commit removes staged files, prepends a commit, and bumps `ahead`; push zeroes `ahead`; pull zeroes `behind`; pop/drop remove a stash.

- [ ] **Step 1: Write the failing tests (append to MockProviderTests.swift)**

Add these methods inside `MockProviderTests`:

```swift
    func test_stageAndUnstageFlipsIsStaged() async throws {
        let p = provider()
        let pkg = Fixtures.files.first { $0.path == "package.json" }!  // starts unstaged
        try await p.stage([pkg])
        var status = try await p.loadStatus()
        XCTAssertTrue(status.files.first { $0.path == "package.json" }!.isStaged)

        try await p.unstage([pkg])
        status = try await p.loadStatus()
        XCTAssertFalse(status.files.first { $0.path == "package.json" }!.isStaged)
    }

    func test_discardRemovesFile() async throws {
        let p = provider()
        let readme = Fixtures.files.first { $0.path == "README.md" }!
        try await p.discard(readme)
        let status = try await p.loadStatus()
        XCTAssertNil(status.files.first { $0.path == "README.md" })
        XCTAssertEqual(status.files.count, 6)
    }

    func test_commitRemovesStagedBumpsAheadAndPrepends() async throws {
        let p = provider()
        let staged = try await p.loadStatus().files.filter(\.isStaged)   // 3 staged
        let new = try await p.commit(message: "Wire it up\n\nbody", staged: staged)
        XCTAssertEqual(new.summary, "Wire it up")
        XCTAssertEqual(new.body, "body")

        let status = try await p.loadStatus()
        XCTAssertEqual(status.files.filter(\.isStaged).count, 0)
        XCTAssertEqual(status.ahead, 3)   // was 2
        let history = try await p.loadHistory(before: nil, limit: 1)
        XCTAssertEqual(history.first?.summary, "Wire it up")
    }

    func test_pushZeroesAheadPullZeroesBehind() async throws {
        let p = provider()
        let pushed = try await p.push()
        XCTAssertEqual(pushed.ahead, 0)
        XCTAssertEqual(try await p.loadStatus().ahead, 0)

        let pulled = try await p.pull()
        XCTAssertEqual(pulled.behind, 0)
        XCTAssertEqual(try await p.loadStatus().behind, 0)
    }

    func test_popAndDropRemoveStashes() async throws {
        let p = provider()
        try await p.popStash(Fixtures.stashes[0])
        var refs = try await p.loadStashes().map(\.ref)
        XCTAssertEqual(refs, ["stash@{1}"])
        try await p.dropStash(Fixtures.stashes[1])
        refs = try await p.loadStashes().map(\.ref)
        XCTAssertEqual(refs, [])
    }

    func test_switchBranchUpdatesCurrent() async throws {
        let p = provider()
        let main = Fixtures.branches.first { $0.name == "main" }!
        try await p.switchBranch(to: main)
        let status = try await p.loadStatus()
        XCTAssertEqual(status.currentBranch, "main")
        let branches = try await p.loadBranches()
        XCTAssertEqual(branches.first(where: \.isCurrent)?.name, "main")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MockProviderTests`
Expected: FAIL — action methods don't exist yet (compile error).

- [ ] **Step 3: Write the implementation (append an extension to MockGitProvider.swift)**

Add to `Sources/GitWorkbench/Provider/MockGitProvider.swift`:

```swift
extension MockGitProvider {

    public func stage(_ files: [FileChange]) async throws {
        await pause()
        setStaged(files.map(\.path), to: true)
    }

    public func unstage(_ files: [FileChange]) async throws {
        await pause()
        setStaged(files.map(\.path), to: false)
    }

    public func discard(_ file: FileChange) async throws {
        await pause()
        status.files.removeAll { $0.path == file.path }
    }

    public func commit(message: String, staged: [FileChange]) async throws -> Commit {
        await pause()
        let stagedPaths = Set(staged.map(\.path))
        status.files.removeAll { stagedPaths.contains($0.path) }
        status.ahead += 1

        let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let summary = lines.first ?? ""
        let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let new = Commit(
            id: "mock\(commits.count)", shortSHA: "mock\(commits.count)",
            summary: summary, body: body,
            authorName: status.author.name, authorEmail: "you@example.com",
            authorInitials: status.author.initials, date: "Just now", relativeDate: "moments ago",
            refs: [.head], parents: commits.first.map { [$0.shortSHA] } ?? [],
            files: staged
        )
        commits.insert(new, at: 0)
        return new
    }

    public func pull() async throws -> SyncResult {
        await pause()
        let pulled = status.behind
        status.behind = 0
        return SyncResult(ahead: status.ahead, behind: 0,
                          message: pulled > 0 ? "Pulled \(pulled) commit(s) from origin" : "Already up to date with origin")
    }

    public func push() async throws -> SyncResult {
        await pause()
        let pushed = status.ahead
        status.ahead = 0
        return SyncResult(ahead: 0, behind: status.behind,
                          message: pushed > 0 ? "Pushed \(pushed) commit(s) to origin" : "Everything up to date")
    }

    public func fetch() async throws -> SyncResult {
        await pause()
        return SyncResult(ahead: status.ahead, behind: status.behind, message: "Up to date with origin")
    }

    public func switchBranch(to branch: Branch) async throws {
        await pause()
        status.currentBranch = branch.name
        status.upstream = branch.upstream
        branches = branches.map {
            Branch(name: $0.name, isCurrent: $0.name == branch.name, upstream: $0.upstream)
        }
    }

    public func applyStash(_ stash: Stash) async throws { await pause() }   // keeps the stash

    public func popStash(_ stash: Stash) async throws {
        await pause()
        stashes.removeAll { $0.id == stash.id }
    }

    public func dropStash(_ stash: Stash) async throws {
        await pause()
        stashes.removeAll { $0.id == stash.id }
    }

    // MARK: Helpers

    private func setStaged(_ paths: [String], to staged: Bool) {
        let set = Set(paths)
        status.files = status.files.map { f in
            guard set.contains(f.path) else { return f }
            return FileChange(id: f.id, path: f.path, status: f.status,
                              isStaged: staged, additions: f.additions, deletions: f.deletions)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MockProviderTests`
Expected: PASS (all ten — four reads + six actions).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: every test passes.

- [ ] **Step 6: Commit**

```bash
git add Sources/GitWorkbench/Provider/MockGitProvider.swift Tests/GitWorkbenchTests/MockProviderTests.swift
git commit -m "Provider: add MockGitProvider action handler (stage/commit/sync/stash mutations)"
```

---

## Self-Review

**1. Spec coverage (vs. `01-architecture.md §1.3` + design spec):**
- `GitWorkbenchProvider` / `GitWorkbenchDataSource` / `GitWorkbenchActionHandler`, `DiffRequest` (+ `Context`), `SyncResult` → Task 1 ✓ (signatures match the handoff verbatim).
- Diff building (port of `hunk()`), unified number assignment → Task 2 ✓; split derivation correctly deferred to the renderer plan.
- Diff content mirroring `gitdata.js` (working/commit/stash), returned by `loadDiff` → Task 3 ✓.
- `MockGitProvider` with seeded reads + mutating actions + small delays (handoff §1.5) → Tasks 4–5 ✓.
- `MockProviderTests` (fixture counts, diffs build, action mutations) per `05 §5.7` → Tasks 4–5 ✓.
- **Deferred by design (Plan 3):** `GitWorkbenchStore`, the store-backed `GitWorkbenchView(store:)`, `GitWorkbenchStore.preview`, the intent→effect reducer + `StoreReducerTests`.

**2. Placeholder scan:** All code steps contain complete code. The only intentional "port verbatim from gitdata.js" delegations are in Task 3's data tables (Step 3), with a fully-worked `sync.ts`/commit/stash example showing the exact pattern and the precise source location + escaping rule — not a vague TODO. The accompanying tests fail loudly if a port is wrong (kind-set assertions, hunk counts).

**3. Type/signature consistency:** `DiffBuilder.hunk(oldStart:newStart:_:)` and `.fileDiff(_:hunks:isBinary:)` defined in Task 2 are used in Tasks 3. `FixtureDiffs.diff(for:context:)` defined in Task 3 is used by `MockGitProvider.loadDiff` in Task 4. `DiffRequest(file:context:mode:)` / `DiffRequest.Context` from Task 1 are used in Tasks 3–4 tests. `MockGitError` (Task 4) used in Task 4 tests. `MockGitProvider(delay:)` is used consistently across Tasks 4–5 tests. Action method signatures match the `GitWorkbenchActionHandler` protocol from Task 1. `FileChange(id:path:status:isStaged:additions:deletions:)` (Plan 1) used in `setStaged`. No mismatches.
