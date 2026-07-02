import XCTest
@testable import GitWorkbenchGitKit
import GitWorkbench

/// Real-`git` coverage for the image/PDF blob loading added in issue #12: `loadDiff` must attach the
/// old/new bytes for a binary the viewer can render, across working-tree / commit contexts, and leave
/// a non-renderable binary as the plain placeholder.
final class CLIGitProviderBinaryTests: XCTestCase {
    private var repo: URL!
    private var provider: CLIGitProvider!

    override func setUp() async throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gwbimg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        provider = CLIGitProvider(repositoryURL: repo)
        try await git(["init", "-b", "main"])
        try await git(["config", "user.email", "t@example.com"])
        try await git(["config", "user.name", "Test User"])
        try await git(["config", "commit.gpgsign", "false"])
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: repo) }

    private func git(_ args: [String]) async throws { _ = try await GitRunner(repositoryURL: repo).output(args) }

    private func writeBytes(_ name: String, _ bytes: [UInt8]) throws {
        let url = repo.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
    }

    /// Bytes git treats as binary (they contain NUL) with a `marker` byte so two versions differ.
    private func png(_ marker: UInt8) -> [UInt8] {
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0x00, count: 12) + [marker, 0xFF, marker]
    }
    private func pdf(_ marker: UInt8) -> [UInt8] { Array("%PDF-1.4\n".utf8) + [0x00, marker, 0x00] + Array("\n%%EOF".utf8) }

    private func loadDiff(_ file: FileChange, _ context: DiffRequest.Context) async throws -> FileDiff {
        try await provider.loadDiff(DiffRequest(file: file, context: context, mode: .split))
    }

    func test_modifiedImage_loadsIndexAndWorkingTreeBytes() async throws {
        try writeBytes("assets/logo.png", png(1))
        try await git(["add", "."]); try await git(["commit", "-m", "add logo"])
        try writeBytes("assets/logo.png", png(2))   // unstaged modification

        let file = FileChange(path: "assets/logo.png", status: .modified, isStaged: false)
        let diff = try await loadDiff(file, .workingTree(staged: false))
        XCTAssertTrue(diff.isBinary)
        XCTAssertTrue(diff.hunks.isEmpty)
        let content = try XCTUnwrap(diff.binaryContent)
        XCTAssertEqual(content.kind, .image)
        XCTAssertEqual(Array(try XCTUnwrap(content.old)), png(1), "old = committed/index version")
        XCTAssertEqual(Array(try XCTUnwrap(content.new)), png(2), "new = working-tree version")
    }

    func test_stagedImage_oldFromHEAD_newFromIndex() async throws {
        try writeBytes("logo.png", png(1))
        try await git(["add", "."]); try await git(["commit", "-m", "v1"])
        try writeBytes("logo.png", png(2)); try await git(["add", "logo.png"])   // staged modification

        let file = FileChange(path: "logo.png", status: .modified, isStaged: true)
        let diff = try await loadDiff(file, .workingTree(staged: true))
        let content = try XCTUnwrap(diff.binaryContent)
        XCTAssertEqual(Array(try XCTUnwrap(content.old)), png(1), "old = HEAD")
        XCTAssertEqual(Array(try XCTUnwrap(content.new)), png(2), "new = index")
    }

    func test_untrackedImage_hasOnlyNew() async throws {
        try writeBytes("a.png", png(7))   // untracked, no commits yet
        let file = FileChange(path: "a.png", status: .untracked, isStaged: false)
        let diff = try await loadDiff(file, .workingTree(staged: false))
        let content = try XCTUnwrap(diff.binaryContent)
        XCTAssertNil(content.old, "untracked file has no index/HEAD version")
        XCTAssertEqual(Array(try XCTUnwrap(content.new)), png(7))
    }

    func test_commitContext_loadsParentAndCommitBlobs() async throws {
        try writeBytes("c.png", png(1)); try await git(["add", "."]); try await git(["commit", "-m", "v1"])
        try writeBytes("c.png", png(2)); try await git(["add", "."]); try await git(["commit", "-m", "v2"])

        let commits = try await provider.loadHistory(of: nil, before: nil, limit: 10)
        let v2 = try XCTUnwrap(commits.first { $0.summary == "v2" })
        let file = try XCTUnwrap(v2.files.first { $0.path == "c.png" })
        let diff = try await loadDiff(file, .commit(v2.id))
        let content = try XCTUnwrap(diff.binaryContent)
        XCTAssertEqual(Array(try XCTUnwrap(content.old)), png(1), "old = parent commit blob")
        XCTAssertEqual(Array(try XCTUnwrap(content.new)), png(2), "new = this commit's blob")
    }

    func test_pdfIsDetectedAsPDFKind() async throws {
        try writeBytes("doc.pdf", pdf(1)); try await git(["add", "."]); try await git(["commit", "-m", "doc v1"])
        try writeBytes("doc.pdf", pdf(2))
        let file = FileChange(path: "doc.pdf", status: .modified, isStaged: false)
        let diff = try await loadDiff(file, .workingTree(staged: false))
        let content = try XCTUnwrap(diff.binaryContent)
        XCTAssertEqual(content.kind, .pdf)
        XCTAssertEqual(Array(try XCTUnwrap(content.new)), pdf(2))
    }

    func test_deletedImage_hasOnlyOld() async throws {
        try writeBytes("gone.png", png(3)); try await git(["add", "."]); try await git(["commit", "-m", "add"])
        try FileManager.default.removeItem(at: repo.appendingPathComponent("gone.png"))   // unstaged deletion

        let file = FileChange(path: "gone.png", status: .deleted, isStaged: false)
        let diff = try await loadDiff(file, .workingTree(staged: false))
        XCTAssertTrue(diff.isBinary)
        let content = try XCTUnwrap(diff.binaryContent)
        XCTAssertEqual(Array(try XCTUnwrap(content.old)), png(3), "old = index blob")
        XCTAssertNil(content.new, "a deleted file has no new side")
    }

    func test_commitContext_rootCommitAdd_hasNoParentBlob() async throws {
        // Binary added in the repo's very first commit: `<root>^` has no parent, so `old` must be nil
        // (git reports "invalid object name"), not an error that misrepresents the add.
        try writeBytes("first.png", png(5)); try await git(["add", "."]); try await git(["commit", "-m", "root"])

        let commits = try await provider.loadHistory(of: nil, before: nil, limit: 10)
        let root = try XCTUnwrap(commits.first { $0.summary == "root" })
        let file = try XCTUnwrap(root.files.first { $0.path == "first.png" })
        let diff = try await loadDiff(file, .commit(root.id))
        let content = try XCTUnwrap(diff.binaryContent)
        XCTAssertNil(content.old, "no parent blob at the root commit")
        XCTAssertEqual(Array(try XCTUnwrap(content.new)), png(5))
    }

    func test_stashContext_loadsBaseAndStashBlobs() async throws {
        try writeBytes("s.png", png(1)); try await git(["add", "."]); try await git(["commit", "-m", "v1"])
        try writeBytes("s.png", png(2)); try await git(["stash", "push", "-m", "wip"])

        let stashes = try await provider.loadStashes()
        let stash = try XCTUnwrap(stashes.first)
        let file = try XCTUnwrap(stash.files.first { $0.path == "s.png" })
        let diff = try await loadDiff(file, .stash(stash.ref))
        XCTAssertTrue(diff.isBinary)
        let content = try XCTUnwrap(diff.binaryContent)
        XCTAssertEqual(Array(try XCTUnwrap(content.old)), png(1), "old = stash base blob")
        XCTAssertEqual(Array(try XCTUnwrap(content.new)), png(2), "new = stash blob")
    }

    func test_nonRenderableBinary_getsNoContent() async throws {
        // A `.bin` is binary to git but not image/PDF → the plain "Binary file" placeholder (nil content).
        try writeBytes("data.bin", [0x00, 0x01, 0x02, 0x00, 0xFF]); try await git(["add", "."]); try await git(["commit", "-m", "bin"])
        try writeBytes("data.bin", [0x00, 0x02, 0x03, 0x00, 0xFE])
        let file = FileChange(path: "data.bin", status: .modified, isStaged: false)
        let diff = try await loadDiff(file, .workingTree(staged: false))
        XCTAssertTrue(diff.isBinary)
        XCTAssertNil(diff.binaryContent, "non-image/PDF binaries keep the placeholder")
    }
}
