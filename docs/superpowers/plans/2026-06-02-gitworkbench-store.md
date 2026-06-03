# GitWorkbench Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `GitWorkbenchStore` — the `@MainActor` `ObservableObject` reducer that drives the whole component — with every intent method (optimistic updates + rollback, busy/toasts, error mapping), a `StoreReducerTests` suite, and the store-backed public `GitWorkbenchView(store:)` init.

**Architecture:** Plan 3 of the program (foundation + provider layer already on `main`). The store is the single source of UI truth: views read `store.state` (a `WorkbenchState` value) and call intent methods; the store mutates state on the main actor and delegates real work to the injected `GitWorkbenchProvider` (the `MockGitProvider` actor from Plan 2). All provider calls are `await`ed off the main actor and results applied back on it. The store class lives in one file (per the handoff layout) organized with same-file extensions; `state`'s setter is `private(set)` (writable from same-file extensions, read-only outside the module).

**Tech Stack:** Swift 6 (language mode), SwiftPM, macOS 15+, XCTest, Combine (`ObservableObject`/`@Published`). No third-party dependencies.

**Conventions for this plan:**
- Behavior follows `docs/design_handoff/05-interactions-a11y.md §5.1` (intent→effect table) and the store API in `01-architecture.md §1.2`.
- TDD: `StoreReducerTests` is `@MainActor`; tests drive the store with `MockGitProvider(delay: .zero)` for determinism, and a `FailingProvider` stub for error paths.
- Run every command from the repo root. Execution happens on a fresh `feat/store` branch off `main`.

---

### Task 1: Store core — state, reload, selection

**Files:**
- Create: `Sources/GitWorkbench/Store/GitWorkbenchStore.swift`
- Test: `Tests/GitWorkbenchTests/StoreReducerTests.swift`

> The class, its init (seeds an empty repo + applies config), `reload()` (parallel loads), the synchronous selection intents, the diff-load helper, the error helper, and the `.preview` convenience. Later tasks append intent extensions to the same file.

- [ ] **Step 1: Write the failing test**

`Tests/GitWorkbenchTests/StoreReducerTests.swift`:

```swift
import XCTest
@testable import GitWorkbench

@MainActor
final class StoreReducerTests: XCTestCase {
    func makeStore() -> GitWorkbenchStore {
        GitWorkbenchStore(provider: MockGitProvider(delay: .zero))
    }

    func test_reloadPopulatesState() async {
        let store = makeStore()
        await store.reload()
        XCTAssertEqual(store.state.repo.repositoryName, "aurora-cli")
        XCTAssertEqual(store.state.repo.files.count, 7)
        XCTAssertEqual(store.state.commits.count, 6)
        XCTAssertEqual(store.state.stashes.count, 2)
        XCTAssertEqual(store.state.branches.count, 4)
    }

    func test_initAppliesConfiguration() {
        var config = WorkbenchConfiguration()
        config.initialView = .history
        config.defaultDiffMode = .unified
        let store = GitWorkbenchStore(provider: MockGitProvider(delay: .zero), configuration: config)
        XCTAssertEqual(store.state.activeView, .history)
        XCTAssertEqual(store.state.diffMode, .unified)
    }

    func test_selectViewDiffModeMessageAndCanCommit() async {
        let store = makeStore()
        await store.reload()
        store.select(.stashes)
        XCTAssertEqual(store.state.activeView, .stashes)
        store.setDiffMode(.unified)
        XCTAssertEqual(store.state.diffMode, .unified)
        store.setCommitMessage("hello")
        XCTAssertTrue(store.state.canCommit)        // 3 staged + message
        store.setCommitMessage("   \n ")
        XCTAssertFalse(store.state.canCommit)        // blank message
    }

    func test_selectFileLoadsWorkingDiff() async {
        let store = makeStore()
        await store.reload()
        let staged = store.state.staged.first!
        store.select(file: staged.id)
        XCTAssertEqual(store.state.selectedFileID, staged.id)
        await store.diffTask?.value
        XCTAssertEqual(store.state.currentDiff?.file.path, staged.path)
    }

    func test_previewStoreIsSeeded() {
        let store = GitWorkbenchStore.preview
        XCTAssertEqual(store.state.repo.files.count, 7)
        XCTAssertNotNil(store.state.selectedFileID)
        XCTAssertNotNil(store.state.currentDiff)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StoreReducerTests`
Expected: FAIL — `GitWorkbenchStore` undefined.

- [ ] **Step 3: Write the implementation**

`Sources/GitWorkbench/Store/GitWorkbenchStore.swift`:

```swift
import Combine
import Foundation

/// The single source of UI truth. Created by the host with a provider; the view observes it.
@MainActor
public final class GitWorkbenchStore: ObservableObject {

    @Published public private(set) var state: WorkbenchState
    public let configuration: WorkbenchConfiguration

    private let provider: any GitWorkbenchProvider

    /// In-flight diff load for the current selection (awaitable in tests).
    private(set) var diffTask: Task<Void, Never>?

    public init(provider: any GitWorkbenchProvider, configuration: WorkbenchConfiguration = .init()) {
        self.provider = provider
        self.configuration = configuration
        let emptyRepo = RepositoryStatus(
            repositoryName: "", currentBranch: "", upstream: nil,
            ahead: 0, behind: 0, files: [], author: Author(name: "", initials: "")
        )
        var initial = WorkbenchState(repo: emptyRepo)
        initial.activeView = configuration.initialView
        initial.diffMode = configuration.defaultDiffMode
        self.state = initial
    }

    // MARK: Loading

    /// Re-pull status, branches, history, and stashes.
    public func reload() async {
        do {
            async let status = provider.loadStatus()
            async let branches = provider.loadBranches()
            async let history = provider.loadHistory(before: nil, limit: 50)
            async let stashes = provider.loadStashes()
            let (s, b, h, st) = try await (status, branches, history, stashes)
            state.repo = s
            state.branches = b
            state.commits = h
            state.stashes = st
        } catch {
            setError(error)
        }
    }

    // MARK: Selection (synchronous intents)

    public func select(_ view: WorkspaceView) { state.activeView = view }
    public func setDiffMode(_ mode: DiffMode) { state.diffMode = mode }
    public func setCommitMessage(_ text: String) { state.commitMessage = text }

    public func select(file id: FileChange.ID) {
        state.selectedFileID = id
        guard let file = state.repo.files.first(where: { $0.id == id }) else {
            state.currentDiff = nil
            return
        }
        let context: DiffRequest.Context = .workingTree(staged: file.isStaged)
        diffTask?.cancel()
        diffTask = Task { [weak self] in
            await self?.loadDiff(for: file, context: context)
        }
    }

    // MARK: Internal helpers (used here and by the intent extensions)

    /// Loads a diff for `file` in `context` and stores it (nil on failure — the pane shows empty).
    func loadDiff(for file: FileChange, context: DiffRequest.Context) async {
        let request = DiffRequest(file: file, context: context, mode: state.diffMode)
        let diff = try? await provider.loadDiff(request)
        if !Task.isCancelled { state.currentDiff = diff }
    }

    /// Maps an error to a toast message and shows it.
    func setError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        state.toast = .error(message)
    }

    // MARK: Convenience

    /// A fully-seeded store for previews and demos (backed by the mock).
    @MainActor public static var preview: GitWorkbenchStore {
        let store = GitWorkbenchStore(provider: MockGitProvider())
        var seeded = Fixtures.initialState
        if let first = seeded.repo.files.first {
            seeded.selectedFileID = first.id
            seeded.currentDiff = FixtureDiffs.diff(for: first, context: .workingTree(staged: first.isStaged))
        }
        store.state = seeded
        return store
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter StoreReducerTests`
Expected: PASS (all five).

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Store/GitWorkbenchStore.swift Tests/GitWorkbenchTests/StoreReducerTests.swift
git commit -m "Store: add GitWorkbenchStore core (state, reload, selection, preview)"
```

---

### Task 2: Staging, discard & commit intents

**Files:**
- Modify: `Sources/GitWorkbench/Store/GitWorkbenchStore.swift` (append an extension)
- Modify: `Tests/GitWorkbenchTests/StoreReducerTests.swift` (append a `FailingProvider` stub + tests)

> Optimistic stage/unstage with rollback on error; discard (with the confirm fields); commit (guarded by `canCommit`). These mutate `state` from a **same-file** extension, so the `private(set)` setter is in scope.

- [ ] **Step 1: Write the failing tests**

Append to `StoreReducerTests.swift` — first a reusable failing provider, then the tests:

```swift
/// A provider whose reads return fixtures but whose actions always throw — for error-path tests.
struct FailingProvider: GitWorkbenchProvider {
    struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }
    func loadStatus() async throws -> RepositoryStatus { Fixtures.repositoryStatus }
    func loadHistory(before: Commit.ID?, limit: Int) async throws -> [Commit] { Fixtures.commits }
    func loadStashes() async throws -> [Stash] { Fixtures.stashes }
    func loadBranches() async throws -> [Branch] { Fixtures.branches }
    func loadDiff(_ request: DiffRequest) async throws -> FileDiff { throw Boom() }
    func stage(_ files: [FileChange]) async throws { throw Boom() }
    func unstage(_ files: [FileChange]) async throws { throw Boom() }
    func discard(_ file: FileChange) async throws { throw Boom() }
    func commit(message: String, staged: [FileChange]) async throws -> Commit { throw Boom() }
    func pull() async throws -> SyncResult { throw Boom() }
    func push() async throws -> SyncResult { throw Boom() }
    func fetch() async throws -> SyncResult { throw Boom() }
    func switchBranch(to branch: Branch) async throws { throw Boom() }
    func applyStash(_ stash: Stash) async throws { throw Boom() }
    func popStash(_ stash: Stash) async throws { throw Boom() }
    func dropStash(_ stash: Stash) async throws { throw Boom() }
}

extension StoreReducerTests {
    func test_toggleStageMovesFileBetweenGroups() async {
        let store = makeStore()
        await store.reload()
        let unstaged = store.state.unstaged.first { $0.path == "package.json" }!
        await store.toggleStage(unstaged.id)
        XCTAssertTrue(store.state.repo.files.first { $0.id == unstaged.id }!.isStaged)
        let staged = store.state.staged.first { $0.path == "src/index.ts" }!
        await store.toggleStage(staged.id)
        XCTAssertFalse(store.state.repo.files.first { $0.id == staged.id }!.isStaged)
    }

    func test_stageAllThenUnstageAll() async {
        let store = makeStore()
        await store.reload()
        await store.stageAll()
        XCTAssertTrue(store.state.unstaged.isEmpty)
        await store.unstageAll()
        XCTAssertTrue(store.state.staged.isEmpty)
    }

    func test_toggleStageRollsBackAndToastsOnError() async {
        let store = GitWorkbenchStore(provider: FailingProvider())
        await store.reload()
        let file = store.state.unstaged.first!
        await store.toggleStage(file.id)
        XCTAssertFalse(store.state.repo.files.first { $0.id == file.id }!.isStaged) // rolled back
        XCTAssertEqual(store.state.toast?.style, .error)
    }

    func test_confirmDiscardRemovesFileAndClearsSelection() async {
        let store = makeStore()
        await store.reload()
        let file = store.state.repo.files.first { $0.path == "README.md" }!
        store.select(file: file.id)
        await store.diffTask?.value
        store.requestDiscard(file.id)
        XCTAssertEqual(store.state.pendingDiscard?.id, file.id)
        await store.confirmDiscard()
        XCTAssertNil(store.state.repo.files.first { $0.id == file.id })
        XCTAssertNil(store.state.selectedFileID)
        XCTAssertNil(store.state.pendingDiscard)
        XCTAssertEqual(store.state.toast?.style, .success)
    }

    func test_commitClearsStagedBumpsAheadPrependsAndToasts() async {
        let store = makeStore()
        await store.reload()
        let aheadBefore = store.state.repo.ahead
        let stagedCount = store.state.staged.count
        store.setCommitMessage("Wire it up")
        await store.commit()
        XCTAssertTrue(store.state.staged.isEmpty)
        XCTAssertEqual(store.state.commitMessage, "")
        XCTAssertEqual(store.state.repo.ahead, aheadBefore + 1)
        XCTAssertEqual(store.state.commits.first?.summary, "Wire it up")
        XCTAssertNil(store.state.selectedFileID)
        XCTAssertEqual(store.state.toast?.style, .success)
        XCTAssertTrue(store.state.toast!.message.contains("\(stagedCount)"))
    }

    func test_commitIsNoOpWhenCannotCommit() async {
        let store = makeStore()
        await store.reload()
        let commitsBefore = store.state.commits.count
        await store.commit()  // no message → guarded
        XCTAssertEqual(store.state.commits.count, commitsBefore)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter StoreReducerTests`
Expected: FAIL — `toggleStage`/`stageAll`/`unstageAll`/`requestDiscard`/`confirmDiscard`/`commit` don't exist (compile error).

- [ ] **Step 3: Write the implementation (append to GitWorkbenchStore.swift)**

```swift
// MARK: - Changes intents

extension GitWorkbenchStore {

    public func toggleStage(_ id: FileChange.ID) async {
        guard let idx = state.repo.files.firstIndex(where: { $0.id == id }) else { return }
        let original = state.repo.files[idx]
        let nowStaged = !original.isStaged
        state.repo.files[idx].isStaged = nowStaged   // optimistic
        do {
            if nowStaged { try await provider.stage([original]) }
            else { try await provider.unstage([original]) }
        } catch {
            if let i = state.repo.files.firstIndex(where: { $0.id == id }) {
                state.repo.files[i].isStaged = original.isStaged   // rollback
            }
            setError(error)
        }
    }

    public func stageAll() async {
        let targets = state.unstaged
        guard !targets.isEmpty else { return }
        let snapshot = state.repo.files
        for i in state.repo.files.indices { state.repo.files[i].isStaged = true }
        do { try await provider.stage(targets) }
        catch { state.repo.files = snapshot; setError(error) }
    }

    public func unstageAll() async {
        let targets = state.staged
        guard !targets.isEmpty else { return }
        let snapshot = state.repo.files
        for i in state.repo.files.indices { state.repo.files[i].isStaged = false }
        do { try await provider.unstage(targets) }
        catch { state.repo.files = snapshot; setError(error) }
    }

    public func requestDiscard(_ id: FileChange.ID) {
        state.pendingDiscard = state.repo.files.first { $0.id == id }
    }

    public func cancelDiscard() { state.pendingDiscard = nil }

    public func confirmDiscard() async {
        guard let file = state.pendingDiscard else { return }
        state.pendingDiscard = nil
        do {
            try await provider.discard(file)
            state.repo.files.removeAll { $0.id == file.id }
            if state.selectedFileID == file.id {
                state.selectedFileID = nil
                state.currentDiff = nil
            }
            state.toast = .success("Discarded changes in \(file.name)")
        } catch {
            setError(error)
        }
    }

    public func commit() async {
        guard state.canCommit else { return }
        let staged = state.staged
        let message = state.commitMessage
        do {
            let newCommit = try await provider.commit(message: message, staged: staged)
            state.repo.files.removeAll { $0.isStaged }
            state.commitMessage = ""
            state.repo.ahead += 1
            state.commits.insert(newCommit, at: 0)
            state.selectedFileID = nil
            state.currentDiff = nil
            state.toast = .success("Committed \(staged.count) file(s) · “\(newCommit.summary)”")
        } catch {
            setError(error)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StoreReducerTests`
Expected: PASS (Task 1 + Task 2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Store/GitWorkbenchStore.swift Tests/GitWorkbenchTests/StoreReducerTests.swift
git commit -m "Store: add staging/discard/commit intents with optimistic rollback"
```

---

### Task 3: Sync & branch intents

**Files:**
- Modify: `Sources/GitWorkbench/Store/GitWorkbenchStore.swift` (append an extension + a small error type)
- Modify: `Tests/GitWorkbenchTests/StoreReducerTests.swift` (append tests)

> pull/push/fetch share a busy + progress→result toast flow; switchBranch reloads. Push-rejected errors map to a friendly message.

- [ ] **Step 1: Write the failing tests**

Append to `StoreReducerTests.swift`:

```swift
extension StoreReducerTests {
    func test_pushZeroesAheadAndShowsSuccessToast() async {
        let store = makeStore()
        await store.reload()
        XCTAssertEqual(store.state.repo.ahead, 2)
        await store.push()
        XCTAssertFalse(store.state.isBusy)
        XCTAssertEqual(store.state.repo.ahead, 0)
        XCTAssertEqual(store.state.toast?.style, .success)
        XCTAssertTrue(store.state.toast!.message.contains("Pushed"))
    }

    func test_pullZeroesBehind() async {
        let store = makeStore()
        await store.reload()
        await store.pull()
        XCTAssertEqual(store.state.repo.behind, 0)
        XCTAssertFalse(store.state.isBusy)
    }

    func test_pushShowsBusyAndProgressWhileInFlight() async {
        let store = GitWorkbenchStore(provider: MockGitProvider(delay: .milliseconds(120)))
        await store.reload()
        let task = Task { await store.push() }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(store.state.isBusy)
        XCTAssertEqual(store.state.toast?.style, .progress)
        await task.value
        XCTAssertFalse(store.state.isBusy)
        XCTAssertEqual(store.state.toast?.style, .success)
    }

    func test_syncErrorClearsBusyAndShowsErrorToast() async {
        let store = GitWorkbenchStore(provider: FailingProvider())
        await store.reload()
        await store.push()
        XCTAssertFalse(store.state.isBusy)
        XCTAssertEqual(store.state.toast?.style, .error)
    }

    func test_switchBranchUpdatesCurrentReloadsAndToasts() async {
        let store = makeStore()
        await store.reload()
        let main = store.state.branches.first { $0.name == "main" }!
        await store.switchBranch(to: main)
        XCTAssertEqual(store.state.repo.currentBranch, "main")
        XCTAssertFalse(store.state.branchMenuOpen)
        XCTAssertEqual(store.state.toast?.message, "Switched to main")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter StoreReducerTests`
Expected: FAIL — `pull`/`push`/`fetch`/`switchBranch` don't exist.

- [ ] **Step 3: Write the implementation (append to GitWorkbenchStore.swift)**

```swift
// MARK: - Sync & branch intents

extension GitWorkbenchStore {

    public func pull() async { await runSync(.pull) }
    public func push() async { await runSync(.push) }
    public func fetch() async { await runSync(.fetch) }

    private enum SyncKind { case pull, push, fetch }

    private func runSync(_ kind: SyncKind) async {
        guard !state.isBusy else { return }
        state.isBusy = true
        switch kind {
        case .pull:  state.toast = .progress("Pulling from origin…")
        case .push:  state.toast = .progress("Pushing to origin…")
        case .fetch: state.toast = .progress("Fetching from origin…")
        }
        do {
            let result: SyncResult
            switch kind {
            case .pull:  result = try await provider.pull()
            case .push:  result = try await provider.push()
            case .fetch: result = try await provider.fetch()
            }
            state.repo.ahead = result.ahead
            state.repo.behind = result.behind
            state.isBusy = false
            state.toast = .success(result.message)
        } catch {
            state.isBusy = false
            setError(mapSyncError(error, kind: kind))
        }
    }

    private func mapSyncError(_ error: Error, kind: SyncKind) -> Error {
        guard kind == .push else { return error }
        let desc = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription).lowercased()
        if desc.contains("reject") || desc.contains("non-fast-forward") {
            return WorkbenchMessageError("Push rejected — pull first")
        }
        return error
    }

    public func switchBranch(to branch: Branch) async {
        state.branchMenuOpen = false
        do {
            try await provider.switchBranch(to: branch)
            await reload()
            state.toast = .success("Switched to \(branch.name)")
        } catch {
            setError(error)
        }
    }
}

/// A simple `LocalizedError` carrying a ready-made message.
struct WorkbenchMessageError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StoreReducerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Store/GitWorkbenchStore.swift Tests/GitWorkbenchTests/StoreReducerTests.swift
git commit -m "Store: add pull/push/fetch (busy + toasts) and switchBranch intents"
```

---

### Task 4: History & stash intents

**Files:**
- Modify: `Sources/GitWorkbench/Store/GitWorkbenchStore.swift` (append an extension)
- Modify: `Tests/GitWorkbenchTests/StoreReducerTests.swift` (append tests)

> Selecting a commit/stash selects its first file and loads that diff; apply keeps the stash; pop/drop remove it and reselect the next.

- [ ] **Step 1: Write the failing tests**

Append to `StoreReducerTests.swift`:

```swift
extension StoreReducerTests {
    func test_selectCommitSelectsFirstFileAndLoadsDiff() async {
        let store = makeStore()
        await store.reload()
        let commit = store.state.commits.first!
        await store.selectCommit(commit.id)
        XCTAssertEqual(store.state.selectedCommitID, commit.id)
        XCTAssertEqual(store.state.selectedCommitFileID, commit.files.first?.id)
        XCTAssertNotNil(store.state.currentDiff)
    }

    func test_selectStashSelectsFirstFileAndLoadsDiff() async {
        let store = makeStore()
        await store.reload()
        let stash = store.state.stashes[0]
        await store.selectStash(stash.id)
        XCTAssertEqual(store.state.selectedStashID, stash.id)
        XCTAssertEqual(store.state.selectedStashFileID, stash.files.first?.id)
        XCTAssertNotNil(store.state.currentDiff)
    }

    func test_applyStashKeepsItAndToasts() async {
        let store = makeStore()
        await store.reload()
        let stash = store.state.stashes[0]
        await store.applyStash(stash.id)
        XCTAssertEqual(store.state.stashes.count, 2)   // kept
        XCTAssertTrue(store.state.toast!.message.contains("Applied"))
    }

    func test_popStashRemovesAndReselectsNext() async {
        let store = makeStore()
        await store.reload()
        let first = store.state.stashes[0]
        await store.popStash(first.id)
        XCTAssertEqual(store.state.stashes.count, 1)
        XCTAssertNil(store.state.stashes.first { $0.id == first.id })
        XCTAssertEqual(store.state.selectedStashID, store.state.stashes.first?.id)
        XCTAssertEqual(store.state.toast?.style, .success)
    }

    func test_dropLastStashClearsSelection() async {
        let store = makeStore()
        await store.reload()
        await store.dropStash(store.state.stashes[0].id)
        await store.dropStash(store.state.stashes[0].id)
        XCTAssertTrue(store.state.stashes.isEmpty)
        XCTAssertNil(store.state.selectedStashID)
        XCTAssertNil(store.state.selectedStashFileID)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter StoreReducerTests`
Expected: FAIL — `selectCommit`/`selectStash`/`applyStash`/`popStash`/`dropStash` don't exist.

- [ ] **Step 3: Write the implementation (append to GitWorkbenchStore.swift)**

```swift
// MARK: - History & stash intents

extension GitWorkbenchStore {

    public func selectCommit(_ id: Commit.ID) async {
        state.selectedCommitID = id
        guard let commit = state.commits.first(where: { $0.id == id }) else { return }
        state.selectedCommitFileID = commit.files.first?.id
        if let first = commit.files.first {
            await loadDiff(for: first, context: .commit(id))
        } else {
            state.currentDiff = nil
        }
    }

    public func selectStash(_ id: Stash.ID) async {
        state.selectedStashID = id
        guard let stash = state.stashes.first(where: { $0.id == id }) else { return }
        state.selectedStashFileID = stash.files.first?.id
        if let first = stash.files.first {
            await loadDiff(for: first, context: .stash(id))
        } else {
            state.currentDiff = nil
        }
    }

    public func applyStash(_ id: Stash.ID) async {
        guard let stash = state.stashes.first(where: { $0.id == id }) else { return }
        do {
            try await provider.applyStash(stash)
            state.toast = .success("Applied \(stash.ref) to working tree")
        } catch {
            setError(error)
        }
    }

    public func popStash(_ id: Stash.ID) async {
        guard let stash = state.stashes.first(where: { $0.id == id }) else { return }
        do {
            try await provider.popStash(stash)
            removeStashAndReselect(id)
            state.toast = .success("Popped \(stash.ref) — “\(stash.message)”")
        } catch {
            setError(error)
        }
    }

    public func dropStash(_ id: Stash.ID) async {
        guard let stash = state.stashes.first(where: { $0.id == id }) else { return }
        do {
            try await provider.dropStash(stash)
            removeStashAndReselect(id)
            state.toast = .success("Dropped \(stash.ref) — “\(stash.message)”")
        } catch {
            setError(error)
        }
    }

    private func removeStashAndReselect(_ id: Stash.ID) {
        guard let idx = state.stashes.firstIndex(where: { $0.id == id }) else { return }
        state.stashes.remove(at: idx)
        guard !state.stashes.isEmpty else {
            state.selectedStashID = nil
            state.selectedStashFileID = nil
            state.currentDiff = nil
            return
        }
        let nextIdx = min(idx, state.stashes.count - 1)
        let next = state.stashes[nextIdx]
        state.selectedStashID = next.id
        state.selectedStashFileID = next.files.first?.id
        if let first = next.files.first {
            diffTask?.cancel()
            diffTask = Task { [weak self] in
                await self?.loadDiff(for: first, context: .stash(next.id))
            }
        } else {
            state.currentDiff = nil
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StoreReducerTests`
Expected: PASS.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: every test passes (Plan 1 + Plan 2 + all StoreReducerTests).

- [ ] **Step 6: Commit**

```bash
git add Sources/GitWorkbench/Store/GitWorkbenchStore.swift Tests/GitWorkbenchTests/StoreReducerTests.swift
git commit -m "Store: add commit/stash selection and apply/pop/drop intents"
```

---

### Task 5: Store-backed `GitWorkbenchView`

**Files:**
- Modify: `Sources/GitWorkbench/GitWorkbenchView.swift`

> Replace the temporary `init(state:configuration:)` with the public `init(store:)`. The view observes the store and reads `store.state`/`store.configuration`; the skeleton subviews are unchanged. Previews use `GitWorkbenchStore.preview`. (No store-level `configuration` param on the view — it reads the store's, the single source of truth. This is a small, intentional simplification of the handoff's `init(store:configuration:)` to avoid two diverging configs.)

- [ ] **Step 1: Replace the file contents**

`Sources/GitWorkbench/GitWorkbenchView.swift`:

```swift
import SwiftUI

/// The reusable git-workbench component. Observes a host-provided `GitWorkbenchStore`.
/// (Plan 3 renders the same themed skeleton as before; later plans add the real
/// toolbar/rail and the three workspace views.)
public struct GitWorkbenchView: View {
    @ObservedObject private var store: GitWorkbenchStore
    @Environment(\.colorScheme) private var colorScheme

    public init(store: GitWorkbenchStore) {
        self.store = store
    }

    private var state: WorkbenchState { store.state }
    private var configuration: WorkbenchConfiguration { store.configuration }

    private var theme: WorkbenchTheme {
        WorkbenchTheme.resolved(for: colorScheme,
                                adoptsSystemAccent: configuration.theme.adoptsSystemAccent)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if configuration.showsToolbar { toolbarSkeleton }
            HStack(spacing: 0) {
                railSkeleton
                bodySkeleton
            }
        }
        .background(theme.winBg)
        .foregroundStyle(theme.ink)
        .task { await store.reload() }
    }

    private var toolbarSkeleton: some View {
        HStack(spacing: 0) {
            Text(state.repo.repositoryName)
                .font(.system(size: 13, weight: .bold))
                .padding(.leading, 20)
                .frame(width: configuration.layout.railWidth, alignment: .leading)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) { Rectangle().fill(theme.sep).frame(width: 1) }
            Spacer(minLength: 0)
        }
        .frame(height: configuration.layout.toolbarHeight)
        .background(theme.titlebar)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }

    private var railSkeleton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WORKSPACE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(theme.ink3)
                .padding(.init(top: 14, leading: 16, bottom: 5, trailing: 16))
            Spacer()
        }
        .frame(width: configuration.layout.railWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(theme.sidebarDeep)
    }

    private var bodySkeleton: some View {
        VStack(spacing: 6) {
            Image(systemName: IconLibrary.file)
                .font(.system(size: 22))
                .foregroundStyle(theme.ink3)
            Text("Select a file to view changes")
                .font(.system(size: 12))
                .foregroundStyle(theme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.winBg)
    }
}

#Preview("Workbench shell — light") {
    GitWorkbenchView(store: .preview)
        .frame(width: 980, height: 600)
}

#Preview("Workbench shell — dark") {
    GitWorkbenchView(store: .preview)
        .frame(width: 980, height: 600)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds (the temporary `init(state:configuration:)` is gone; nothing else referenced it).

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 4: Verify previews render**

Open `Package.swift` in Xcode and resume the canvas for `GitWorkbenchView.swift`. Confirm both previews show the seeded skeleton (repo name "aurora-cli", rail, empty-state body) in light and dark — driven by `GitWorkbenchStore.preview`.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/GitWorkbenchView.swift
git commit -m "View: switch GitWorkbenchView to store-backed public init(store:)"
```

---

## Self-Review

**1. Spec coverage (vs. `01-architecture.md §1.2` + `05 §5.1` + `§5.7`):**
- `init(provider:configuration:)`, `@Published private(set) state`, `reload()`, `select(_:)`, `select(file:)`, `setDiffMode`, `setCommitMessage` → Task 1 ✓
- `toggleStage`/`stageAll`/`unstageAll`/`requestDiscard`/`confirmDiscard`/`cancelDiscard`/`commit` → Task 2 ✓ (optimistic + rollback; commit guarded)
- `pull`/`push`/`fetch`/`switchBranch` → Task 3 ✓ (busy + progress→result toasts; push-rejected mapping)
- `selectCommit`/`selectStash`/`applyStash`/`popStash`/`dropStash` → Task 4 ✓
- `preview` → Task 1 ✓; store-backed `GitWorkbenchView(store:)` → Task 5 ✓
- `StoreReducerTests` covering toggleStage, commit, confirmDiscard, pop/drop, switchBranch, sync busy/toasts, and provider-error rollback (`§5.7`) → Tasks 1–4 ✓
- **Intentional deviations (noted in-plan):** (a) the view's `init` drops the redundant `configuration:` param and reads `store.configuration`; (b) toast auto-dismiss timing (`§4.5`) is deferred to the polish plan — the store only sets the current toast.

**2. Placeholder scan:** Every step has complete code + exact commands. The Task 3 test note explicitly tells the implementer to OMIT the one line (`store.state.branchMenuOpen = true`) that wouldn't compile from the test module (the setter is `private(set)`), keeping the remaining assertions valid — that is a guard against a compile error, not a placeholder.

**3. Type/signature consistency:** `GitWorkbenchStore(provider:configuration:)`, `state` (`WorkbenchState`), `diffTask`, `loadDiff(for:context:)`, and `setError(_:)` defined in Task 1 are used by the extensions in Tasks 2–4. All intent signatures match `01 §1.2` (`toggleStage(_:) async`, `select(file:)`, `switchBranch(to:) async`, `applyStash(_:) async`, etc.). `MockGitProvider(delay:)`, `Fixtures`, `FixtureDiffs.diff(for:context:)`, `DiffRequest(file:context:mode:)`, `SyncResult`, `Toast.success/.error/.progress`, and `FileChange.isStaged` (mutable) are all from Plans 1–2 and used consistently. `WorkbenchMessageError` (Task 3) is the only new helper type. `GitWorkbenchView(store:)` (Task 5) matches the `.preview` type from Task 1.
