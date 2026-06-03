import XCTest
import Foundation
@testable import GitWorkbenchGitKit

final class RepositoryWatcherTests: XCTestCase {

    // MARK: - Pure relevance filter (deterministic, no FSEvents)

    func test_isRelevant_ignoresRootAndBuildOutput() {
        let root = "/repo"
        // The bare watched root is FSEvents' coarse "something changed under here" signal — not on its own.
        XCTAssertFalse(RepositoryWatcher.isRelevant([root], root: root))
        // Build / cache dirs git already ignores.
        XCTAssertFalse(RepositoryWatcher.isRelevant([root, root + "/.build"], root: root))
        XCTAssertFalse(RepositoryWatcher.isRelevant([root + "/.build/x.o", root + "/.build/x.o.sb-tmp"], root: root))
        XCTAssertFalse(RepositoryWatcher.isRelevant([root + "/DerivedData/m", root + "/node_modules/p"], root: root))
    }

    func test_isRelevant_acceptsSourceAndGitChanges() {
        let root = "/repo"
        XCTAssertTrue(RepositoryWatcher.isRelevant([root + "/Sources/a.swift"], root: root))
        // .git churn is how we notice external commits / branch switches / stashes — it must count.
        XCTAssertTrue(RepositoryWatcher.isRelevant([root + "/.git/index"], root: root))
        // A real edit mixed in with root + ignored noise still triggers.
        XCTAssertTrue(RepositoryWatcher.isRelevant([root, root + "/.build", root + "/src/file.txt"], root: root))
    }

    // MARK: - End-to-end stream smoke test

    func test_firesOnFileChange() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gwbwatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let signal = DispatchSemaphore(value: 0)
        let watcher = RepositoryWatcher(url: dir, debounce: 0.2) { signal.signal() }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.6)   // let the stream arm before we touch anything
        try "hello\n".write(to: dir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        XCTAssertEqual(signal.wait(timeout: .now() + 6), .success, "watcher should report a real change")
    }
}
