import XCTest
@testable import GitWorkbench

final class SmokeTests: XCTestCase {
    func test_moduleLoads() {
        XCTAssertEqual(GitWorkbenchInfo.version, "0.1.0")
    }
}
