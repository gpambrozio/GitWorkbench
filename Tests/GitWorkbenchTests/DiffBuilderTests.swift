import XCTest
@testable import GitWorkbench

final class DiffBuilderTests: XCTestCase {
    func test_interleavedHunkAssignsNumbersAndHeader() {
        let h = DiffBuilder.hunk(oldStart: 14, newStart: 14, [
            " context",
            "-removed",
            "+added",
            " context2",
        ])
        XCTAssertEqual(h.lines.map(\.kind), [.context, .deletion, .addition, .context])
        XCTAssertEqual(h.lines.map(\.oldNumber), [14, 15, nil, 16])
        XCTAssertEqual(h.lines.map(\.newNumber), [14, nil, 15, 16])
        XCTAssertEqual(h.lines.map(\.text), ["context", "removed", "added", "context2"])
        // old count = context+deletion = 3; new count = context+addition = 3
        XCTAssertEqual(h.header, "@@ -14,3 +14,3 @@")
    }

    func test_pureAddHunk() {
        let h = DiffBuilder.hunk(oldStart: 0, newStart: 1, ["+a", "+b", "+c"])
        XCTAssertEqual(h.lines.map(\.kind), [.addition, .addition, .addition])
        XCTAssertEqual(h.lines.map(\.oldNumber), [nil, nil, nil])
        XCTAssertEqual(h.lines.map(\.newNumber), [1, 2, 3])
        // old count = 0; new count = 3
        XCTAssertEqual(h.header, "@@ -0,0 +1,3 @@")
    }

    func test_pureDeleteHunk() {
        let h = DiffBuilder.hunk(oldStart: 1, newStart: 0, ["-x", "-y"])
        XCTAssertEqual(h.lines.map(\.kind), [.deletion, .deletion])
        XCTAssertEqual(h.lines.map(\.oldNumber), [1, 2])
        XCTAssertEqual(h.lines.map(\.newNumber), [nil, nil])
        XCTAssertEqual(h.header, "@@ -1,2 +0,0 @@")
    }

    func test_emptyPrefixedLinesKeepEmptyText() {
        let h = DiffBuilder.hunk(oldStart: 1, newStart: 1, [" ", "+", "-"])
        XCTAssertEqual(h.lines.map(\.text), ["", "", ""])
        XCTAssertEqual(h.lines.map(\.kind), [.context, .addition, .deletion])
    }
}
