import XCTest
@testable import GitWorkbenchGitKit

final class GitRunnerTests: XCTestCase {
    func test_runsGitVersionInThisRepo() async throws {
        // This repo is a real git repo; `git -C . rev-parse --is-inside-work-tree` → "true".
        let runner = GitRunner(repositoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let result = try await runner.output(["rev-parse", "--is-inside-work-tree"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.text.trimmingCharacters(in: .whitespacesAndNewlines), "true")
    }

    func test_nonzeroExitThrows() async {
        let runner = GitRunner(repositoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        do {
            _ = try await runner.output(["cat-file", "-e", "0000000000000000000000000000000000000000"])
            XCTFail("expected failure")
        } catch let error as GitError {
            if case .commandFailed = error {} else { XCTFail("wrong error: \(error)") }
        } catch { XCTFail("wrong error type") }
    }
}
