import XCTest
@testable import GitWorkbenchGitKit
import GitWorkbench

final class CLIGitProviderActionTests: XCTestCase {
    private var repo: URL!
    private var provider: CLIGitProvider!

    override func setUp() async throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gwbact-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        provider = CLIGitProvider(repositoryURL: repo)
        let r = GitRunner(repositoryURL: repo)
        _ = try await r.output(["init", "-b", "main"])
        _ = try await r.output(["config", "user.email", "t@example.com"])
        _ = try await r.output(["config", "user.name", "Test User"])
        _ = try await r.output(["config", "commit.gpgsign", "false"])
        try "v1\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await r.output(["add", "a.txt"]); _ = try await r.output(["commit", "-m", "init"])
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: repo) }

    func test_stageThenUnstage() async throws {
        try "v2\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let file = FileChange(path: "a.txt", status: .modified)
        try await provider.stage([file])
        let staged = try await provider.loadStatus().files
        XCTAssertTrue(staged.contains { $0.path == "a.txt" && $0.isStaged })
        try await provider.unstage([file])
        let unstaged = try await provider.loadStatus().files
        XCTAssertTrue(unstaged.contains { $0.path == "a.txt" && !$0.isStaged })
    }

    func test_commitGrowsHistory() async throws {
        try "fresh\n".write(to: repo.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try await provider.stage([FileChange(path: "b.txt", status: .added)])
        let new = try await provider.commit(message: "add b", staged: [FileChange(path: "b.txt", status: .added)])
        XCTAssertEqual(new.summary, "add b")
        let history = try await provider.loadHistory(of: nil, before: nil, limit: 10)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.summary, "add b")
        XCTAssertEqual(new.id, history.first?.id)
    }

    func test_discardRevertsModification() async throws {
        try "changed\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try await provider.discard(FileChange(path: "a.txt", status: .modified))
        let contents = try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(contents, "v1\n")
    }

    func test_discardRemovesUntrackedFile() async throws {
        let scratch = repo.appendingPathComponent("scratch.txt")
        try "temp\n".write(to: scratch, atomically: true, encoding: .utf8)
        try await provider.discard(FileChange(path: "scratch.txt", status: .untracked))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.path))   // clean -fd removed it
    }

    func test_discardRevertsStagedModification() async throws {
        // Regression: discarding a STAGED file must reset the index too, not just the worktree —
        // otherwise the staged change survives and reappears on the next status read.
        try "changed\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try await provider.stage([FileChange(path: "a.txt", status: .modified)])
        try await provider.discard(FileChange(path: "a.txt", status: .modified, isStaged: true))
        let contents = try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(contents, "v1\n")                                        // worktree reverted
        let files = try await provider.loadStatus().files
        XCTAssertTrue(files.isEmpty, "staged file should be fully gone from status, got \(files)")
    }

    func test_discardRestoresStagedDeletion() async throws {
        _ = try await GitRunner(repositoryURL: repo).output(["rm", "a.txt"])    // staged deletion
        try await provider.discard(FileChange(path: "a.txt", status: .deleted, isStaged: true))
        let contents = try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(contents, "v1\n")                                        // file restored from HEAD
        let files = try await provider.loadStatus().files
        XCTAssertTrue(files.isEmpty, "staged deletion should be fully discarded, got \(files)")
    }

    func test_discardRemovesStagedAddedFile() async throws {
        try "brand new\n".write(to: repo.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        try await provider.stage([FileChange(path: "c.txt", status: .added)])
        try await provider.discard(FileChange(path: "c.txt", status: .added, isStaged: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent("c.txt").path))
        let files = try await provider.loadStatus().files
        XCTAssertTrue(files.isEmpty, "staged-added file should be removed, got \(files)")
    }

    func test_switchBranch() async throws {
        _ = try await GitRunner(repositoryURL: repo).output(["branch", "dev"])
        try await provider.switchBranch(to: Branch(name: "dev"))
        let branch = try await provider.loadStatus().currentBranch
        XCTAssertEqual(branch, "dev")
    }

    func test_checkoutRemoteBranchCreatesLocalTrackingBranch() async throws {
        let r = GitRunner(repositoryURL: repo)
        let origin = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gwbremote-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: origin) }
        _ = try await r.output(["init", "--bare", origin.path])
        _ = try await r.output(["remote", "add", "origin", origin.path])
        _ = try await r.output(["branch", "feature/x"])
        _ = try await r.output(["push", "origin", "main", "feature/x"])
        _ = try await r.output(["branch", "-D", "feature/x"]) // exists only on the remote now
        _ = try await r.output(["fetch", "origin"])

        try await provider.checkoutRemoteBranch(RemoteBranch(remote: "origin", name: "feature/x"))
        let current = try await provider.loadStatus().currentBranch
        XCTAssertEqual(current, "feature/x")
        let upstream = try await r.output(["rev-parse", "--abbrev-ref", "feature/x@{upstream}"]).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(upstream, "origin/feature/x") // the new local branch tracks the remote
    }

    func test_checkoutRemoteBranchSwitchesToExistingLocalBranch() async throws {
        let r = GitRunner(repositoryURL: repo)
        let origin = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gwbremote-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: origin) }
        _ = try await r.output(["init", "--bare", origin.path])
        _ = try await r.output(["remote", "add", "origin", origin.path])
        _ = try await r.output(["push", "origin", "main"])
        _ = try await r.output(["fetch", "origin"])
        _ = try await r.output(["switch", "-c", "other"]) // move off main so the switch is observable

        // Local "main" already exists, so checking out the remote should just switch to it (no error).
        try await provider.checkoutRemoteBranch(RemoteBranch(remote: "origin", name: "main"))
        let current = try await provider.loadStatus().currentBranch
        XCTAssertEqual(current, "main")
    }

    func test_stashApplyAndDrop() async throws {
        try "wip\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await GitRunner(repositoryURL: repo).output(["stash", "push", "-m", "wip"])
        let stash = try await provider.loadStashes()[0]
        try await provider.applyStash(stash)
        let afterApply = try await provider.loadStashes().count
        XCTAssertEqual(afterApply, 1)
        try await provider.dropStash(stash)
        let afterDrop = try await provider.loadStashes().count
        XCTAssertEqual(afterDrop, 0)
    }

    func test_stashPopRestoresAndRemoves() async throws {
        try "wip2\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await GitRunner(repositoryURL: repo).output(["stash", "push", "-m", "wip2"])
        let stash = try await provider.loadStashes()[0]
        try await provider.popStash(stash)
        let restored = try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(restored, "wip2\n")                       // working change restored
        let count = try await provider.loadStashes().count
        XCTAssertEqual(count, 0)                                 // and the stash is gone
    }

    // MARK: - Commit context-menu actions

    /// A bare `Commit` carrying only the SHA — the action methods read `commit.id` and nothing else.
    private func stubCommit(_ sha: String) -> Commit {
        Commit(id: sha, shortSHA: String(sha.prefix(7)), summary: "", authorName: "",
               authorEmail: "", authorInitials: "", date: "", relativeDate: "")
    }

    /// Commits a new file and returns the resulting SHA.
    private func commitFile(_ name: String, _ contents: String, message: String) async throws -> String {
        let r = GitRunner(repositoryURL: repo)
        try contents.write(to: repo.appendingPathComponent(name), atomically: true, encoding: .utf8)
        _ = try await r.output(["add", name])
        _ = try await r.output(["commit", "-m", message])
        return try await r.output(["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func test_checkoutDetachesHeadAtCommit() async throws {
        let first = try await GitRunner(repositoryURL: repo)
            .output(["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await commitFile("b.txt", "b\n", message: "second")

        try await provider.checkout(stubCommit(first))
        let head = try await GitRunner(repositoryURL: repo)
            .output(["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(head, first)   // HEAD now at the first commit
    }

    func test_resetHEADHardMovesHeadAndDiscardsChanges() async throws {
        let first = try await GitRunner(repositoryURL: repo)
            .output(["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await commitFile("b.txt", "b\n", message: "second")

        try await provider.resetHEAD(to: stubCommit(first), mode: .hard)
        let head = try await GitRunner(repositoryURL: repo)
            .output(["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(head, first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent("b.txt").path))
    }

    func test_resetHEADSoftKeepsChangesStaged() async throws {
        let first = try await GitRunner(repositoryURL: repo)
            .output(["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await commitFile("b.txt", "b\n", message: "second")

        try await provider.resetHEAD(to: stubCommit(first), mode: .soft)
        let files = try await provider.loadStatus().files
        XCTAssertTrue(files.contains { $0.path == "b.txt" && $0.isStaged })   // change preserved, staged
    }

    func test_revertCreatesInverseCommit() async throws {
        let sha = try await commitFile("b.txt", "b\n", message: "add b")
        try await provider.revert(stubCommit(sha))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent("b.txt").path))
        let history = try await provider.loadHistory(of: nil, before: nil, limit: 10)
        XCTAssertEqual(history.count, 3)                          // init, add b, revert
        XCTAssertTrue(history.first?.summary.hasPrefix("Revert") ?? false)
    }

    func test_cherryPickAppliesCommitOntoCurrentBranch() async throws {
        let r = GitRunner(repositoryURL: repo)
        _ = try await r.output(["switch", "-c", "feature"])
        let sha = try await commitFile("feature.txt", "feat\n", message: "add feature file")
        _ = try await r.output(["switch", "main"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent("feature.txt").path))

        try await provider.cherryPick(stubCommit(sha))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.appendingPathComponent("feature.txt").path))
    }

    func test_createBranchAtCommitWithoutSwitching() async throws {
        let head = try await GitRunner(repositoryURL: repo)
            .output(["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines)
        try await provider.createBranch(named: "topic", at: stubCommit(head))
        let branches = try await provider.loadBranches()
        XCTAssertTrue(branches.contains { $0.name == "topic" })
        let current = try await provider.loadStatus().currentBranch
        XCTAssertEqual(current, "main")   // did not switch
    }

    func test_createTagAtCommit() async throws {
        let head = try await GitRunner(repositoryURL: repo)
            .output(["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines)
        try await provider.createTag(named: "v1.0", at: stubCommit(head))
        let tags = try await GitRunner(repositoryURL: repo).output(["tag", "--list"]).text
        XCTAssertTrue(tags.contains("v1.0"))
    }
}
