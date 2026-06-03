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
