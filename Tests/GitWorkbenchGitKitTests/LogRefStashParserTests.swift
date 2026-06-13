import XCTest
@testable import GitWorkbenchGitKit
import GitWorkbench

final class LogRefStashParserTests: XCTestCase {
    func test_logParsesCommits() {
        let F = "\u{1f}", R = "\u{1e}"
        let record = ["9f2c1a4e7b3","9f2c1a4","Gustavo Ambrozio","g@x.dev","2026-06-01T09:42:00-03:00",
                      "2026-06-01T09:42:00-03:00","3b8e7d2f1a9","HEAD -> feat/x, tag: v1.0, origin/feat/x",
                      "Add the thing","body line 1\nbody line 2"].joined(separator: F)
        let commits = LogParser.parse(record + R)
        XCTAssertEqual(commits.count, 1)
        let c = commits[0]
        XCTAssertEqual(c.shortSHA, "9f2c1a4")
        XCTAssertEqual(c.summary, "Add the thing")
        XCTAssertEqual(c.authorName, "Gustavo Ambrozio")
        XCTAssertEqual(c.authorInitials, "GA")
        XCTAssertEqual(c.parents, ["3b8e7d2f1a9"])
        XCTAssertTrue(c.refs.contains(.head))
        XCTAssertTrue(c.refs.contains(.branch("feat/x")))
        XCTAssertTrue(c.refs.contains(.tag("v1.0")))
        XCTAssertTrue(c.body.contains("body line 1"))
    }

    func test_refParsesBranches() {
        let F = "\u{1f}"
        let lines = ["main\(F)origin/main\(F)*", "feat/x\(F)origin/feat/x\(F)", "dev\(F)\(F)"]
        let branches = RefParser.parse(lines.joined(separator: "\n"))
        XCTAssertEqual(branches.map(\.name), ["main", "feat/x", "dev"])
        XCTAssertEqual(branches.first(where: { $0.name == "main" })?.upstream, "origin/main")
        XCTAssertTrue(branches.first(where: { $0.name == "main" })!.isCurrent)
        XCTAssertNil(branches.first(where: { $0.name == "dev" })?.upstream)
    }

    func test_remoteRefParsesBranchesStrippingRemotePrefix() {
        let F = "\u{1f}"
        let lines = ["origin/main\(F)main",
                     "origin/feat/auto-sync\(F)feat/auto-sync",   // branch name keeps its own slashes
                     "origin/HEAD\(F)HEAD",                        // the remote's HEAD pointer — dropped
                     "upstream/main\(F)main"]
        let branches = RemoteRefParser.parse(lines.joined(separator: "\n"))
        XCTAssertEqual(branches.map(\.name), ["main", "feat/auto-sync", "main"])  // prefix removed, HEAD skipped
        XCTAssertEqual(branches.map(\.id), ["origin/main", "origin/feat/auto-sync", "upstream/main"])
        XCTAssertEqual(branches.map(\.remote), ["origin", "origin", "upstream"])
    }

    func test_stashParsesEntries() {
        let F = "\u{1f}"
        let lines = ["stash@{0}\(F)WIP: tune retry delays\(F)40 minutes ago",
                     "stash@{1}\(F)experiment\(F)2 days ago"]
        let stashes = StashParser.parse(lines.joined(separator: "\n"), branch: "feat/x")
        XCTAssertEqual(stashes.map(\.ref), ["stash@{0}", "stash@{1}"])
        XCTAssertEqual(stashes[0].message, "WIP: tune retry delays")
        XCTAssertEqual(stashes[0].relativeDate, "40 minutes ago")
        XCTAssertEqual(stashes[0].id, "stash@{0}")
    }

    func test_initialsHelper() {
        XCTAssertEqual(LogParser.initials(for: "Gustavo Ambrozio"), "GA")
        XCTAssertEqual(LogParser.initials(for: "madonna"), "M")
        XCTAssertEqual(LogParser.initials(for: ""), "?")
    }
}
