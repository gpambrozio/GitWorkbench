import XCTest
@testable import GitWorkbenchGitKit
import GitWorkbench

final class DiffParserTests: XCTestCase {
    private let sample = """
    diff --git a/src/a.swift b/src/a.swift
    index 1111111..2222222 100644
    --- a/src/a.swift
    +++ b/src/a.swift
    @@ -1,3 +1,4 @@
     import Foundation
    -let x = 1
    +let x = 2
    +let y = 3
     // end
    @@ -10,2 +11,2 @@
    -old
    +new
    """

    func test_parsesHunksAndLines() {
        let file = FileChange(path: "src/a.swift", status: .modified)
        let diff = DiffParser.parse(unifiedDiff: sample, file: file)
        XCTAssertEqual(diff.hunks.count, 2)
        XCTAssertFalse(diff.isBinary)
        XCTAssertTrue(diff.hunks[0].header.hasPrefix("@@ -1,"))
        let kinds = diff.hunks[0].lines.map(\.kind)
        XCTAssertEqual(kinds, [.context, .deletion, .addition, .addition, .context])
        // first context line: old 1 / new 1; first addition: new 2 (after the deletion at old 2)
        XCTAssertEqual(diff.hunks[0].lines[0].oldNumber, 1)
        XCTAssertEqual(diff.hunks[0].lines[1].oldNumber, 2)   // deletion advances old
        XCTAssertEqual(diff.hunks[0].lines[2].newNumber, 2)   // addition advances new
        XCTAssertEqual(diff.hunks[0].lines.map(\.text)[1], "let x = 1")
    }

    func test_detectsBinary() {
        let bin = "diff --git a/x.png b/x.png\nBinary files a/x.png and b/x.png differ\n"
        let diff = DiffParser.parse(unifiedDiff: bin, file: FileChange(path: "x.png", status: .modified))
        XCTAssertTrue(diff.isBinary)
        XCTAssertTrue(diff.hunks.isEmpty)
    }

    func test_emptyDiffYieldsNoHunks() {
        let diff = DiffParser.parse(unifiedDiff: "", file: FileChange(path: "x", status: .modified))
        XCTAssertTrue(diff.hunks.isEmpty)
    }

    func test_trailingNewlineDoesNotAddPhantomLine() {
        // Real `git diff` output is newline-terminated; the trailing empty split element must NOT
        // become a phantom blank context line on the last hunk.
        let withNewline = "@@ -1,2 +1,2 @@\n-old\n+new\n context\n"
        let diff = DiffParser.parse(unifiedDiff: withNewline, file: FileChange(path: "x", status: .modified))
        XCTAssertEqual(diff.hunks.count, 1)
        XCTAssertEqual(diff.hunks[0].lines.map(\.kind), [.deletion, .addition, .context])
        XCTAssertEqual(diff.hunks[0].lines.count, 3)   // no phantom 4th line
    }
}
