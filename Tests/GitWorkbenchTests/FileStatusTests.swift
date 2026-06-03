import XCTest
@testable import GitWorkbench

final class FileStatusTests: XCTestCase {
    func test_rawValuesMatchGitGlyphs() {
        XCTAssertEqual(FileStatus.modified.rawValue, "M")
        XCTAssertEqual(FileStatus.added.rawValue, "A")
        XCTAssertEqual(FileStatus.deleted.rawValue, "D")
        XCTAssertEqual(FileStatus.renamed.rawValue, "R")
        XCTAssertEqual(FileStatus.untracked.rawValue, "U")
        XCTAssertEqual(FileStatus.conflicted.rawValue, "!")
    }

    func test_longLabels() {
        XCTAssertEqual(FileStatus.modified.label, "Modified")
        XCTAssertEqual(FileStatus.added.label, "Added")
        XCTAssertEqual(FileStatus.deleted.label, "Deleted")
        XCTAssertEqual(FileStatus.renamed.label, "Renamed")
        XCTAssertEqual(FileStatus.untracked.label, "Untracked")
        XCTAssertEqual(FileStatus.conflicted.label, "Conflicted")
    }
}
