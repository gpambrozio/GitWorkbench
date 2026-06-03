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
