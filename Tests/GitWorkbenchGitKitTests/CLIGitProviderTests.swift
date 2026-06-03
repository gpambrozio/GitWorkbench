import XCTest
@testable import GitWorkbenchGitKit
import GitWorkbench

final class CLIGitProviderTests: XCTestCase {
    private var repo: URL!
    private var provider: CLIGitProvider!

    override func setUp() async throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gwbtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        provider = CLIGitProvider(repositoryURL: repo)
        // Build a small real repo.
        try await git(["init", "-b", "main"])
        try await git(["config", "user.email", "t@example.com"])
        try await git(["config", "user.name", "Test User"])
        try await git(["config", "commit.gpgsign", "false"])
        try write("a.txt", "one\ntwo\nthree\n")
        try await git(["add", "a.txt"])
        try await git(["commit", "-m", "first commit"])
        // a committed second file + an unstaged edit + a staged new file + an untracked file
        try write("a.txt", "one\nTWO\nthree\nfour\n")    // unstaged modify
        try write("b.txt", "new file\n"); try await git(["add", "b.txt"])  // staged add
        try write("c.txt", "untracked\n")               // untracked
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: repo)
    }

    private func git(_ args: [String]) async throws {
        _ = try await GitRunner(repositoryURL: repo).output(args)
    }
    private func write(_ name: String, _ contents: String) throws {
        try contents.write(to: repo.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func test_validatePasses() async throws { try await provider.validate() }

    func test_loadStatusReadsRealWorkingTree() async throws {
        let status = try await provider.loadStatus()
        XCTAssertEqual(status.currentBranch, "main")
        XCTAssertEqual(status.repositoryName, repo.lastPathComponent)
        // a.txt unstaged-modified, b.txt staged-added, c.txt untracked
        XCTAssertTrue(status.files.contains { $0.path == "a.txt" && !$0.isStaged && $0.status == .modified })
        XCTAssertTrue(status.files.contains { $0.path == "b.txt" && $0.isStaged && $0.status == .added })
        XCTAssertTrue(status.files.contains { $0.path == "c.txt" && $0.status == .untracked })
        // numstat merged: a.txt has +1 (added "four") and the modified line nets +1/-1
        let a = status.files.first { $0.path == "a.txt" }!
        XCTAssertGreaterThan(a.additions, 0)
    }

    func test_loadHistoryAndCommitFiles() async throws {
        let commits = try await provider.loadHistory(before: nil, limit: 10)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].summary, "first commit")
        XCTAssertEqual(commits[0].authorName, "Test User")
        XCTAssertEqual(commits[0].authorInitials, "TU")
        XCTAssertEqual(commits[0].files.map(\.path), ["a.txt"])
        XCTAssertEqual(commits[0].files.first?.status, .added)
    }

    func test_loadBranches() async throws {
        let branches = try await provider.loadBranches()
        XCTAssertEqual(branches.map(\.name), ["main"])
        XCTAssertTrue(branches[0].isCurrent)
    }

    func test_loadDiffForWorkingTreeFile() async throws {
        let file = FileChange(path: "a.txt", status: .modified, isStaged: false)
        let diff = try await provider.loadDiff(DiffRequest(file: file, context: .workingTree(staged: false), mode: .unified))
        XCTAssertFalse(diff.hunks.isEmpty)
        XCTAssertTrue(diff.hunks.flatMap { $0.lines }.contains { $0.kind == .addition })
    }

    func test_loadStashes() async throws {
        try await git(["stash", "push", "-u", "-m", "wip stash"])
        let stashes = try await provider.loadStashes()
        XCTAssertEqual(stashes.count, 1)
        XCTAssertTrue(stashes[0].message.contains("wip stash"))
        XCTAssertFalse(stashes[0].files.isEmpty)
    }

    func test_loadStatusCountsRenamedFile() async throws {
        // A staged rename+edit must carry numstat counts. Regression: `--numstat -z` renders a rename
        // as "<add>\t<del>\t" \0 old \0 new \0, and the counts were being keyed under the empty path.
        try write("r.txt", "a\nb\nc\nd\ne\n")
        try await git(["add", "r.txt"]); try await git(["commit", "-m", "add r"])
        try await git(["mv", "r.txt", "r2.txt"])
        try write("r2.txt", "a\nb\nC\nd\ne\nf\n")   // change one line + append one → high similarity → rename
        try await git(["add", "r2.txt"])

        let status = try await provider.loadStatus()
        let renamed = status.files.first { $0.path == "r2.txt" && $0.isStaged }
        XCTAssertNotNil(renamed, "staged rename should surface under the new path")
        XCTAssertEqual(renamed?.status, .renamed)
        XCTAssertGreaterThan(renamed?.additions ?? 0, 0, "renamed file must carry its numstat additions")
    }

    func test_loadHistoryPagingPastRootReturnsEmpty() async throws {
        let commits = try await provider.loadHistory(before: nil, limit: 10)
        XCTAssertEqual(commits.count, 1)            // setUp makes exactly one (root) commit
        let older = try await provider.loadHistory(before: commits[0].id, limit: 10)
        XCTAssertTrue(older.isEmpty, "paging before the root commit must return empty, not throw")
    }
}
