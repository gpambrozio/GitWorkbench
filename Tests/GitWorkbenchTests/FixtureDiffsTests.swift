import XCTest
@testable import GitWorkbench

final class FixtureDiffsTests: XCTestCase {
    func test_workingTreeDiffForSyncHasTwoHunks() {
        let file = Fixtures.files.first { $0.path == "src/commands/sync.ts" }!
        let diff = FixtureDiffs.diff(for: file, context: .workingTree(staged: true))!
        XCTAssertEqual(diff.hunks.count, 2)
        XCTAssertEqual(diff.file.path, "src/commands/sync.ts")
        XCTAssertFalse(diff.isBinary)
        // first hunk starts at old/new line 14
        XCTAssertTrue(diff.hunks[0].header.hasPrefix("@@ -14,"))
    }

    func test_addedFileDiffIsAllAdditions() {
        let logger = Fixtures.files.first { $0.path == "src/utils/logger.ts" }!
        let diff = FixtureDiffs.diff(for: logger, context: .workingTree(staged: true))!
        let kinds = Set(diff.hunks.flatMap { $0.lines.map(\.kind) })
        XCTAssertEqual(kinds, [.addition])
    }

    func test_deletedFileDiffIsAllDeletions() {
        let poller = Fixtures.files.first { $0.path == "src/legacy/poller.ts" }!
        let diff = FixtureDiffs.diff(for: poller, context: .workingTree(staged: false))!
        let kinds = Set(diff.hunks.flatMap { $0.lines.map(\.kind) })
        XCTAssertEqual(kinds, [.deletion])
    }

    func test_commitDiffResolvesByCommitAndPath() {
        let commit = Fixtures.commits.first { $0.shortSHA == "9f2c1a4" }!
        let file = commit.files.first { $0.path == "src/commands/sync.ts" }!
        let diff = FixtureDiffs.diff(for: file, context: .commit(commit.id))
        XCTAssertNotNil(diff)
        XCTAssertFalse(diff!.hunks.isEmpty)
    }

    func test_stashDiffResolvesByStashAndPath() {
        let stash = Fixtures.stashes[0]
        let file = stash.files[0]
        let diff = FixtureDiffs.diff(for: file, context: .stash(stash.id))
        XCTAssertNotNil(diff)
        XCTAssertFalse(diff!.hunks.isEmpty)
    }

    func test_unknownFileReturnsNil() {
        let ghost = FileChange(path: "does/not/exist.txt", status: .modified)
        XCTAssertNil(FixtureDiffs.diff(for: ghost, context: .workingTree(staged: false)))
    }
}
