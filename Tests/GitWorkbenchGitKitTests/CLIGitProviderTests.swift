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
        let commits = try await provider.loadHistory(of: nil, before: nil, limit: 10)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].summary, "first commit")
        XCTAssertEqual(commits[0].authorName, "Test User")
        XCTAssertEqual(commits[0].authorInitials, "TU")
        XCTAssertEqual(commits[0].files.map(\.path), ["a.txt"])
        XCTAssertEqual(commits[0].files.first?.status, .added)
    }

    func test_loadHistoryOfSpecificBranch() async throws {
        // A second commit on main, then a feature branch off the root with its own commit.
        try write("a.txt", "v2\n")
        try await git(["commit", "-am", "main second"])
        try await git(["checkout", "-b", "feature", "HEAD~1"])
        try write("f.txt", "feat\n")
        try await git(["add", "f.txt"])
        try await git(["commit", "-m", "feature work"])
        try await git(["checkout", "main"])

        let main = try await provider.loadHistory(of: "main", before: nil, limit: 10)
        XCTAssertEqual(main.map(\.summary), ["main second", "first commit"])
        let feature = try await provider.loadHistory(of: "feature", before: nil, limit: 10)
        XCTAssertEqual(feature.map(\.summary), ["feature work", "first commit"])
        // nil starts at the current branch (main)
        let current = try await provider.loadHistory(of: nil, before: nil, limit: 10)
        XCTAssertEqual(current.map(\.summary), main.map(\.summary))
    }

    func test_loadBranches() async throws {
        let branches = try await provider.loadBranches()
        XCTAssertEqual(branches.map(\.name), ["main"])
        XCTAssertTrue(branches[0].isCurrent)
        XCTAssertNil(branches[0].upstream)      // no remote yet → no divergence
        XCTAssertEqual(branches[0].ahead, 0)
        XCTAssertEqual(branches[0].behind, 0)
    }

    func test_loadBranchesReportsAheadBehindAgainstUpstream() async throws {
        let origin = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gwbremote-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: origin) }
        try await git(["init", "--bare", origin.path])
        try await git(["remote", "add", "origin", origin.path])
        try await git(["push", "-u", "origin", "main"])   // main tracks origin/main, in sync

        // A commit pushed to origin, then reset away locally → local main is 1 commit behind.
        try write("d.txt", "on origin\n"); try await git(["add", "d.txt"])
        try await git(["commit", "-m", "second"])
        try await git(["push"])                            // origin/main advances to "second"
        try await git(["reset", "--hard", "HEAD~1"])       // local main falls back → behind 1

        // A commit origin doesn't have → local main is also 1 commit ahead.
        try write("e.txt", "local only\n"); try await git(["add", "e.txt"])
        try await git(["commit", "-m", "local only"])

        let main = try await provider.loadBranches().first { $0.name == "main" }
        XCTAssertEqual(main?.upstream, "origin/main")
        XCTAssertEqual(main?.ahead, 1)   // "local only"
        XCTAssertEqual(main?.behind, 1)  // "second"
    }

    func test_loadRemoteBranchesStripsPrefixAndSkipsHEAD() async throws {
        let origin = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gwbremote-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: origin) }
        try await git(["init", "--bare", origin.path])
        try await git(["remote", "add", "origin", origin.path])
        try await git(["branch", "feature/x"])
        try await git(["push", "origin", "main", "feature/x"])
        try await git(["fetch", "origin"])
        try await git(["remote", "set-head", "origin", "main"]) // creates the origin/HEAD pointer

        let remotes = try await provider.loadRemoteBranches()
        XCTAssertEqual(Set(remotes.map(\.name)), ["main", "feature/x"]) // remote prefix removed
        XCTAssertEqual(Set(remotes.map(\.id)), ["origin/main", "origin/feature/x"])
        XCTAssertTrue(remotes.allSatisfy { $0.remote == "origin" })
        XCTAssertFalse(remotes.contains { $0.name == "HEAD" }) // origin/HEAD is not a branch
    }

    func test_loadDiffForWorkingTreeFile() async throws {
        let file = FileChange(path: "a.txt", status: .modified, isStaged: false)
        let diff = try await provider.loadDiff(DiffRequest(file: file, context: .workingTree(staged: false), mode: .unified))
        XCTAssertFalse(diff.hunks.isEmpty)
        XCTAssertTrue(diff.hunks.flatMap { $0.lines }.contains { $0.kind == .addition })
    }

    func test_loadDiffForUntrackedFileShowsContentAsAdditions() async throws {
        // c.txt ("untracked\n") is untracked; `git diff -- c.txt` is empty, so we use --no-index
        // to show its whole content as added lines instead of a blank pane.
        let file = FileChange(path: "c.txt", status: .untracked, isStaged: false)
        let diff = try await provider.loadDiff(DiffRequest(file: file, context: .workingTree(staged: false), mode: .unified))
        let lines = diff.hunks.flatMap { $0.lines }
        XCTAssertFalse(lines.isEmpty, "untracked file diff should show its content")
        XCTAssertTrue(lines.allSatisfy { $0.kind == .addition }, "every line is an addition")
        XCTAssertTrue(lines.contains { $0.text.contains("untracked") })
    }

    func test_loadStashes() async throws {
        try await git(["stash", "push", "-u", "-m", "wip stash"])
        let stashes = try await provider.loadStashes()
        XCTAssertEqual(stashes.count, 1)
        XCTAssertTrue(stashes[0].message.contains("wip stash"))
        XCTAssertFalse(stashes[0].files.isEmpty)
    }

    func test_loadDiffForStashedFile() async throws {
        // The per-file stash diff must have hunks. Regression: `git stash show -p <id> -- <path>`
        // fails ("Too many revisions specified") because stash show takes no pathspec.
        try await git(["stash", "push", "-m", "wip"])          // stashes a.txt (modified) + b.txt (staged)
        let stash = try await provider.loadStashes()[0]
        let file = try XCTUnwrap(stash.files.first { $0.path == "a.txt" }, "stash should contain a.txt")
        let diff = try await provider.loadDiff(DiffRequest(file: file, context: .stash(stash.id), mode: .unified))
        XCTAssertFalse(diff.hunks.isEmpty, "a stashed file's diff should render hunks")
        XCTAssertTrue(diff.hunks.flatMap { $0.lines }.contains { $0.kind == .addition || $0.kind == .deletion })
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
        let commits = try await provider.loadHistory(of: nil, before: nil, limit: 10)
        XCTAssertEqual(commits.count, 1)            // setUp makes exactly one (root) commit
        let older = try await provider.loadHistory(of: nil, before: commits[0].id, limit: 10)
        XCTAssertTrue(older.isEmpty, "paging before the root commit must return empty, not throw")
    }

    func test_repositoryChangesIsNilWhenWatchingDisabled() {
        let provider = CLIGitProvider(repositoryURL: repo, watchesFileSystem: false)
        XCTAssertNil(provider.repositoryChanges(), "opting out must disable the change stream")
    }

    func test_repositoryChangesEmitsWhenAFileChanges() async throws {
        // Default provider watches the working tree.
        let stream = try XCTUnwrap(provider.repositoryChanges())
        let received = expectation(description: "change emitted")
        let consumer = Task {
            for await _ in stream { received.fulfill(); break }
        }
        // Let FSEvents arm, then change a file on disk (no git involved).
        try await Task.sleep(for: .milliseconds(400))
        try write("watched.txt", "touched\n")
        await fulfillment(of: [received], timeout: 5)
        consumer.cancel()
    }
}
