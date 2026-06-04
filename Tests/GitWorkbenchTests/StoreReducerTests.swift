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

    func test_showHistorySetsBranchAndView() async {
        let store = makeStore()
        await store.reload()
        await store.showHistory(of: Branch(name: "feature-x"))
        XCTAssertEqual(store.state.activeView, .history)
        XCTAssertEqual(store.state.historyBranch, "feature-x")
        XCTAssertFalse(store.state.commits.isEmpty)
        XCTAssertNotNil(store.state.selectedCommitID)   // tip auto-selected
    }

    func test_setThemeUpdatesConfiguration() {
        let store = makeStore()
        var custom = WorkbenchTheme.standard
        custom.adoptsSystemAccent = true                 // a flag we can assert without Color equality
        store.setTheme(light: custom, dark: custom)
        XCTAssertTrue(store.configuration.theme.adoptsSystemAccent)
        XCTAssertTrue(store.configuration.darkTheme.adoptsSystemAccent)
    }

    func test_switchBranchClearsHistoryBranch() async {
        let store = makeStore()
        await store.reload()
        await store.showHistory(of: Branch(name: "feature-x"))
        XCTAssertEqual(store.state.historyBranch, "feature-x")
        await store.switchBranch(to: Branch(name: "main"))
        XCTAssertNil(store.state.historyBranch)            // history follows the new current branch
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

/// A provider whose reads return fixtures but whose actions always throw — for error-path tests.
struct FailingProvider: GitWorkbenchProvider {
    struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }
    func loadStatus() async throws -> RepositoryStatus { Fixtures.repositoryStatus }
    func loadHistory(of ref: String?, before: Commit.ID?, limit: Int) async throws -> [Commit] { Fixtures.commits }
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
