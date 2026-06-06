import XCTest
@testable import GitWorkbench

final class RepositorySummaryTests: XCTestCase {
    private func makeState(
        files: [FileChange] = [],
        ahead: Int = 0,
        behind: Int = 0,
        upstream: String? = nil,
        repositoryName: String = "demo",
        currentBranch: String = "main",
        isBusy: Bool = false
    ) -> WorkbenchState {
        let repo = RepositoryStatus(
            repositoryName: repositoryName, currentBranch: currentBranch, upstream: upstream,
            ahead: ahead, behind: behind, files: files, author: Author(name: "Dev", initials: "DV")
        )
        var s = WorkbenchState(repo: repo)
        s.isBusy = isBusy
        return s
    }

    func test_derivesCountsAndChurnFromFiles() {
        let files = [
            FileChange(path: "a.txt", status: .modified, isStaged: true, additions: 10, deletions: 2),
            FileChange(path: "b.txt", status: .added, isStaged: false, additions: 5, deletions: 0),
            FileChange(path: "c.txt", status: .deleted, isStaged: false, additions: 0, deletions: 7),
        ]
        let summary = RepositorySummary(state: makeState(files: files))
        XCTAssertEqual(summary.changedFileCount, 3)
        XCTAssertEqual(summary.stagedCount, 1)
        XCTAssertEqual(summary.unstagedCount, 2)
        XCTAssertEqual(summary.additions, 15)
        XCTAssertEqual(summary.deletions, 9)
    }

    func test_hasConflictsWhenAnyFileConflicted() {
        let conflicted = FileChange(path: "merge.txt", status: .conflicted)
        let clean = FileChange(path: "ok.txt", status: .modified)
        XCTAssertTrue(RepositorySummary(state: makeState(files: [clean, conflicted])).hasConflicts)
        XCTAssertFalse(RepositorySummary(state: makeState(files: [clean])).hasConflicts)
    }

    func test_syncFlagsDeriveFromAheadBehindAndUpstream() {
        let ahead = RepositorySummary(state: makeState(ahead: 2, behind: 0, upstream: "origin/main"))
        XCTAssertEqual(ahead.ahead, 2)
        XCTAssertTrue(ahead.needsPush)
        XCTAssertFalse(ahead.needsPull)
        XCTAssertTrue(ahead.hasUpstream)

        let behind = RepositorySummary(state: makeState(ahead: 0, behind: 3, upstream: nil))
        XCTAssertEqual(behind.behind, 3)
        XCTAssertFalse(behind.needsPush)
        XCTAssertTrue(behind.needsPull)
        XCTAssertFalse(behind.hasUpstream)
    }

    func test_isCleanRequiresNoFilesAndNoAheadBehind() {
        XCTAssertTrue(RepositorySummary(state: makeState()).isClean)
        // Something to push/pull is not clean, even with no changed files.
        XCTAssertFalse(RepositorySummary(state: makeState(ahead: 1)).isClean)
        XCTAssertFalse(RepositorySummary(state: makeState(behind: 1)).isClean)
        // A changed file is not clean.
        let f = FileChange(path: "a.txt", status: .modified)
        XCTAssertFalse(RepositorySummary(state: makeState(files: [f])).isClean)
    }

    func test_carriesBranchRepositoryNameAndBusyFlag() {
        let summary = RepositorySummary(
            state: makeState(repositoryName: "aurora-cli", currentBranch: "feat/sync", isBusy: true)
        )
        XCTAssertEqual(summary.repositoryName, "aurora-cli")
        XCTAssertEqual(summary.currentBranch, "feat/sync")
        XCTAssertTrue(summary.isBusy)
    }
}
