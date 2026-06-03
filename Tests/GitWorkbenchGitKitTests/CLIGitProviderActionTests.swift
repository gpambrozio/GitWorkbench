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
        let history = try await provider.loadHistory(before: nil, limit: 10)
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

    func test_switchBranch() async throws {
        _ = try await GitRunner(repositoryURL: repo).output(["branch", "dev"])
        try await provider.switchBranch(to: Branch(name: "dev"))
        let branch = try await provider.loadStatus().currentBranch
        XCTAssertEqual(branch, "dev")
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
}
