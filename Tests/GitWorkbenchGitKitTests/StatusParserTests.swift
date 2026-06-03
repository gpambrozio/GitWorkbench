import XCTest
@testable import GitWorkbenchGitKit
import GitWorkbench

final class StatusParserTests: XCTestCase {
    // Porcelain v2 -z --branch: NUL-separated records. (Use \u{0} between records.)
    private let sample = [
        "# branch.oid abc123",
        "# branch.head feat/x",
        "# branch.upstream origin/feat/x",
        "# branch.ab +2 -1",
        "1 M. N... 100644 100644 100644 h1 h2 src/staged.swift",
        "1 .M N... 100644 100644 100644 h1 h2 src/unstaged.swift",
        "1 MM N... 100644 100644 100644 h1 h2 src/both.swift",
        "1 A. N... 000000 100644 100644 h1 h2 added.swift",
        "1 .D N... 100644 100644 100644 h1 h2 gone.swift",
        "? untracked.txt",
        "u UU N... 100644 100644 100644 100644 h1 h2 h3 conflict.swift",
    ].joined(separator: "\u{0}") + "\u{0}"

    func test_parsesBranchInfo() {
        let result = StatusParser.parse(porcelain: sample)
        XCTAssertEqual(result.branch, "feat/x")
        XCTAssertEqual(result.upstream, "origin/feat/x")
        XCTAssertEqual(result.ahead, 2)
        XCTAssertEqual(result.behind, 1)
    }

    func test_partitionsStagedAndUnstaged() {
        let files = StatusParser.parse(porcelain: sample).files
        // staged.swift (staged, M), both.swift:staged (staged, M), added.swift (staged, A)
        let staged = files.filter(\.isStaged).map(\.path).sorted()
        XCTAssertEqual(staged, ["added.swift", "src/both.swift", "src/staged.swift"])
        // unstaged: unstaged.swift, both.swift:unstaged, gone.swift, untracked.txt, conflict.swift
        let unstaged = files.filter { !$0.isStaged }.map(\.path).sorted()
        XCTAssertEqual(unstaged, ["conflict.swift", "gone.swift", "src/both.swift", "src/unstaged.swift", "untracked.txt"])
    }

    func test_bothModifiedFileGetsSuffixedIDs() {
        let files = StatusParser.parse(porcelain: sample).files.filter { $0.path == "src/both.swift" }
        XCTAssertEqual(Set(files.map(\.id)), ["src/both.swift:staged", "src/both.swift:unstaged"])
    }

    func test_mapsStatusCodes() {
        let files = StatusParser.parse(porcelain: sample).files
        func status(_ path: String, staged: Bool) -> FileStatus? {
            files.first { $0.path == path && $0.isStaged == staged }?.status
        }
        XCTAssertEqual(status("added.swift", staged: true), .added)
        XCTAssertEqual(status("gone.swift", staged: false), .deleted)
        XCTAssertEqual(status("untracked.txt", staged: false), .untracked)
        XCTAssertEqual(status("conflict.swift", staged: false), .conflicted)
    }

    func test_numstatParsesCounts() {
        let numstat = ["24\t6\tsrc/a.swift", "0\t18\tsrc/b.swift", "-\t-\tbinary.png"].joined(separator: "\u{0}") + "\u{0}"
        let counts = NumstatParser.parse(numstat)
        XCTAssertEqual(counts["src/a.swift"]?.additions, 24)
        XCTAssertEqual(counts["src/a.swift"]?.deletions, 6)
        XCTAssertEqual(counts["src/b.swift"]?.deletions, 18)
        XCTAssertEqual(counts["binary.png"]?.additions, 0)   // "-" (binary) → 0
    }

    func test_numstatHandlesRenameTriple() {
        // Real `git --numstat -z` renders a rename/copy as "<add>\t<del>\t" \0 old \0 new \0
        // (empty path field, old + new as their own records). Counts must key by the NEW path.
        let numstat = ["1\t0\t", "old.txt", "new.txt", "3\t1\tplain.swift"].joined(separator: "\u{0}") + "\u{0}"
        let counts = NumstatParser.parse(numstat)
        XCTAssertEqual(counts["new.txt"]?.additions, 1)
        XCTAssertEqual(counts["new.txt"]?.deletions, 0)
        XCTAssertNil(counts["old.txt"])      // the old path is not a key
        XCTAssertNil(counts[""])             // counts must NOT land under the empty path field
        XCTAssertEqual(counts["plain.swift"]?.additions, 3)   // a following normal entry still parses
    }
}
