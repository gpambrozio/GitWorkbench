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
        let firstTwo = try await p.loadHistory(of: nil, before: nil, limit: 2)
        XCTAssertEqual(firstTwo.map(\.shortSHA), ["9f2c1a4", "3b8e7d2"])
        // page older than the 2nd commit
        let next = try await p.loadHistory(of: nil, before: firstTwo[1].id, limit: 2)
        XCTAssertEqual(next.map(\.shortSHA), ["a17f9c0", "e4d5b61"])
    }

    func test_loadStashesAndBranches() async throws {
        let p = provider()
        let stashes = try await p.loadStashes()
        XCTAssertEqual(stashes.map(\.ref), ["stash@{0}", "stash@{1}"])
        let branches = try await p.loadBranches()
        XCTAssertEqual(branches.first(where: \.isCurrent)?.name, "feat/auto-sync")
        let remotes = try await p.loadRemoteBranches()
        XCTAssertEqual(remotes.map(\.name), ["develop", "feat/auto-sync", "main", "release/1.0"])
        XCTAssertEqual(remotes.first?.id, "origin/develop") // id keeps the remote prefix
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
        let history = try await p.loadHistory(of: nil, before: nil, limit: 1)
        XCTAssertEqual(history.first?.summary, "Wire it up")
    }

    func test_pushZeroesAheadPullZeroesBehind() async throws {
        let p = provider()
        let pushed = try await p.push()
        XCTAssertEqual(pushed.ahead, 0)
        let statusAfterPush = try await p.loadStatus()
        XCTAssertEqual(statusAfterPush.ahead, 0)

        let pulled = try await p.pull()
        XCTAssertEqual(pulled.behind, 0)
        let statusAfterPull = try await p.loadStatus()
        XCTAssertEqual(statusAfterPull.behind, 0)
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

    func test_checkoutRemoteBranchTracksAndCreatesLocalBranch() async throws {
        let p = provider()
        // release/1.0 exists only as a remote branch (no local counterpart).
        let release = Fixtures.remoteBranches.first { $0.name == "release/1.0" }!
        try await p.checkoutRemoteBranch(release)
        let status = try await p.loadStatus()
        XCTAssertEqual(status.currentBranch, "release/1.0")
        XCTAssertEqual(status.upstream, "origin/release/1.0")
        let branches = try await p.loadBranches()
        XCTAssertEqual(branches.first(where: \.isCurrent)?.name, "release/1.0")
        XCTAssertTrue(branches.contains { $0.name == "release/1.0" }) // local tracking branch created
    }
}
