import XCTest
@testable import GitWorkbench

final class WorkbenchStateTests: XCTestCase {
    private func makeState(files: [FileChange], message: String = "") -> WorkbenchState {
        let repo = RepositoryStatus(
            repositoryName: "demo", currentBranch: "main", ahead: 0, behind: 0,
            files: files, author: Author(name: "Dev", initials: "DV")
        )
        var s = WorkbenchState(repo: repo)
        s.commitMessage = message
        return s
    }

    func test_stagedAndUnstagedPartitionByFlag() {
        let staged = FileChange(path: "a.txt", status: .modified, isStaged: true)
        let unstaged = FileChange(path: "b.txt", status: .modified, isStaged: false)
        let s = makeState(files: [staged, unstaged])
        XCTAssertEqual(s.staged.map(\.id), ["a.txt"])
        XCTAssertEqual(s.unstaged.map(\.id), ["b.txt"])
    }

    func test_canCommitRequiresStagedFileAndNonBlankMessage() {
        let staged = FileChange(path: "a.txt", status: .modified, isStaged: true)

        XCTAssertFalse(makeState(files: [staged], message: "").canCommit)        // no message
        XCTAssertFalse(makeState(files: [staged], message: "   \n").canCommit)   // blank message
        XCTAssertFalse(makeState(files: [], message: "msg").canCommit)           // nothing staged
        XCTAssertTrue(makeState(files: [staged], message: "fix bug").canCommit)  // both present
    }
}
