import XCTest
@testable import GitWorkbench

final class DiffSplitterTests: XCTestCase {
    private func line(_ kind: DiffLine.Kind, o: Int?, n: Int?, _ text: String) -> DiffLine {
        DiffLine(kind: kind, oldNumber: o, newNumber: n, text: text)
    }

    func test_pureAdditions_leftEmptyRightAdds() {
        let rows = DiffSplitter.rows([
            line(.addition, o: nil, n: 1, "a"),
            line(.addition, o: nil, n: 2, "b"),
        ])
        XCTAssertEqual(rows.count, 2)
        XCTAssertNil(rows[0].left); XCTAssertEqual(rows[0].right?.text, "a")
        XCTAssertNil(rows[1].left); XCTAssertEqual(rows[1].right?.text, "b")
    }

    func test_pureDeletions_rightEmptyLeftDels() {
        let rows = DiffSplitter.rows([
            line(.deletion, o: 1, n: nil, "x"),
            line(.deletion, o: 2, n: nil, "y"),
        ])
        XCTAssertEqual(rows.map { $0.left?.text }, ["x", "y"])
        XCTAssertEqual(rows.map { $0.right?.text }, [nil, nil])
    }

    func test_interleaved_zipsAndPads() {
        // ctx, del, del, add, ctx  →  ctx/ctx, (d1|a1), (d2|·), ctx/ctx
        let rows = DiffSplitter.rows([
            line(.context, o: 1, n: 1, "c1"),
            line(.deletion, o: 2, n: nil, "d1"),
            line(.deletion, o: 3, n: nil, "d2"),
            line(.addition, o: nil, n: 2, "a1"),
            line(.context, o: 4, n: 3, "c2"),
        ])
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].left?.text, "c1"); XCTAssertEqual(rows[0].right?.text, "c1")
        XCTAssertEqual(rows[1].left?.text, "d1"); XCTAssertEqual(rows[1].right?.text, "a1")
        XCTAssertEqual(rows[2].left?.text, "d2"); XCTAssertNil(rows[2].right)
        XCTAssertEqual(rows[3].left?.text, "c2"); XCTAssertEqual(rows[3].right?.text, "c2")
    }

    func test_context_showsOldOnLeftNewOnRight() {
        let rows = DiffSplitter.rows([line(.context, o: 5, n: 7, "ctx")])
        XCTAssertEqual(rows[0].left?.oldNumber, 5)
        XCTAssertEqual(rows[0].right?.newNumber, 7)
    }

    func test_rowIDsAreStableAcrossCalls() {
        let lines = [line(.deletion, o: 1, n: nil, "x"), line(.addition, o: nil, n: 1, "y")]
        XCTAssertEqual(DiffSplitter.rows(lines).map(\.id), DiffSplitter.rows(lines).map(\.id))
    }
}
