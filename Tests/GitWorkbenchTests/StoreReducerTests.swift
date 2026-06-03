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
