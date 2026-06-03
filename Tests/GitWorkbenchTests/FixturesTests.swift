import XCTest
@testable import GitWorkbench

final class FixturesTests: XCTestCase {
    func test_repositoryHeadline() {
        let s = Fixtures.repositoryStatus
        XCTAssertEqual(s.repositoryName, "aurora-cli")
        XCTAssertEqual(s.currentBranch, "feat/auto-sync")
        XCTAssertEqual(s.upstream, "origin/feat/auto-sync")
        XCTAssertEqual(s.ahead, 2)
        XCTAssertEqual(s.behind, 1)
        XCTAssertEqual(s.author, Author(name: "Gustavo", initials: "GA"))
    }

    func test_fileCountsAndStagedSplit() {
        XCTAssertEqual(Fixtures.repositoryStatus.files.count, 7)
        let staged = Fixtures.repositoryStatus.files.filter(\.isStaged)
        let unstaged = Fixtures.repositoryStatus.files.filter { !$0.isStaged }
        XCTAssertEqual(staged.map(\.path), ["src/commands/sync.ts", "src/index.ts", "src/utils/logger.ts"])
        XCTAssertEqual(unstaged.count, 4)
    }

    func test_commitCountAndRefs() {
        XCTAssertEqual(Fixtures.commits.count, 6)
        XCTAssertEqual(Fixtures.commits.first?.shortSHA, "9f2c1a4")
        XCTAssertEqual(Fixtures.commits.first?.refs, [.head, .branch("feat/auto-sync")])
        XCTAssertEqual(Fixtures.commits.first(where: { $0.shortSHA == "a17f9c0" })?.refs, [.tag("v0.5.0-rc.1")])
    }

    func test_stashAndBranchCounts() {
        XCTAssertEqual(Fixtures.stashes.count, 2)
        XCTAssertEqual(Fixtures.stashes.first?.ref, "stash@{0}")
        XCTAssertEqual(Fixtures.branches.map(\.name), ["main", "develop", "feat/auto-sync", "fix/log-levels"])
        XCTAssertEqual(Fixtures.branches.first(where: \.isCurrent)?.name, "feat/auto-sync")
    }

    func test_initialStateBuildsFromFixtures() {
        let s = Fixtures.initialState
        XCTAssertEqual(s.repo.files.count, 7)
        XCTAssertEqual(s.commits.count, 6)
        XCTAssertEqual(s.stashes.count, 2)
        XCTAssertEqual(s.branches.count, 4)
    }
}
