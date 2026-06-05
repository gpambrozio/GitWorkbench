import XCTest
@testable import GitWorkbench

final class FileChangeTests: XCTestCase {
    func test_derivesDirectoryAndNameFromNestedPath() {
        let f = FileChange(path: "src/commands/sync.ts", status: .modified,
                           isStaged: true, additions: 24, deletions: 6)
        XCTAssertEqual(f.directory, "src/commands")
        XCTAssertEqual(f.name, "sync.ts")
        XCTAssertEqual(f.id, "src/commands/sync.ts")   // id defaults to the path
    }

    func test_derivesEmptyDirectoryForRootFile() {
        let f = FileChange(path: "package.json", status: .modified,
                           isStaged: false, additions: 3, deletions: 1)
        XCTAssertEqual(f.directory, "")
        XCTAssertEqual(f.name, "package.json")
    }

    func test_explicitIDOverridesPath() {
        let f = FileChange(id: "src/index.ts:staged", path: "src/index.ts",
                           status: .modified, isStaged: true, additions: 8, deletions: 2)
        XCTAssertEqual(f.id, "src/index.ts:staged")
        XCTAssertEqual(f.name, "index.ts")
    }

    func test_urlRelativeToRoot_resolvesAgainstRepositoryRoot() {
        let f = FileChange(path: "src/commands/sync.ts", status: .modified)
        let url = f.url(relativeTo: URL(filePath: "/Users/me/repo"))
        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(url.path, "/Users/me/repo/src/commands/sync.ts")
    }

    func test_urlRelativeToNilRoot_isRepoRelativeURL() {
        let f = FileChange(path: "src/commands/sync.ts", status: .modified)
        let url = f.url(relativeTo: nil)
        XCTAssertTrue(url.isFileURL)
        // No root to resolve against → the URL is repo-relative: relativePath preserves the path, but the
        // absolute path is cwd-resolved (not a usable repo location), which is exactly why a host should
        // set `repositoryURL`.
        XCTAssertEqual(url.relativePath, "src/commands/sync.ts")
        XCTAssertNotEqual(url.path, "src/commands/sync.ts")
        XCTAssertTrue(url.path.hasSuffix("/src/commands/sync.ts"))
    }
}
