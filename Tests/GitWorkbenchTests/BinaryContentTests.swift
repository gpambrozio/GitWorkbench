import XCTest
@testable import GitWorkbench

final class BinaryContentTests: XCTestCase {

    func test_kindForPath_recognizesImages() {
        for ext in ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "ico"] {
            XCTAssertEqual(BinaryContent.kind(forPath: "assets/pic.\(ext)"), .image, ext)
            XCTAssertEqual(BinaryContent.kind(forPath: "PIC.\(ext.uppercased())"), .image, "case-insensitive \(ext)")
        }
    }

    func test_kindForPath_recognizesPDF() {
        XCTAssertEqual(BinaryContent.kind(forPath: "docs/spec.pdf"), .pdf)
        XCTAssertEqual(BinaryContent.kind(forPath: "SPEC.PDF"), .pdf)
    }

    func test_kindForPath_returnsNilForNonRenderable() {
        for path in ["src/a.swift", "notes.txt", "noextension", "bundle.zip", "vector.svg", "movie.mp4"] {
            XCTAssertNil(BinaryContent.kind(forPath: path), path)
        }
    }

    func test_fileDiffMarksBinaryWhenContentPresent() {
        let file = FileChange(path: "logo.png", status: .modified)
        let diff = FileDiff(file: file, hunks: [],
                            binaryContent: BinaryContent(kind: .image, old: Data([0x1]), new: Data([0x2])))
        XCTAssertTrue(diff.isBinary, "carrying binary content implies isBinary")
        XCTAssertNotNil(diff.binaryContent)
    }

    func test_fileDiffTextDiffStaysNonBinary() {
        let diff = FileDiff(file: FileChange(path: "a.swift", status: .modified), hunks: [])
        XCTAssertFalse(diff.isBinary)
        XCTAssertNil(diff.binaryContent)
    }

    // MARK: Fixtures wire real image/PDF bytes for the mock-backed demo & previews.

    func test_fixtureModifiedImageHasBothSides() throws {
        let banner = Fixtures.files.first { $0.path == "assets/banner.png" }!
        let diff = try XCTUnwrap(FixtureDiffs.diff(for: banner, context: .workingTree(staged: false)))
        XCTAssertTrue(diff.isBinary)
        let content = try XCTUnwrap(diff.binaryContent)
        XCTAssertEqual(content.kind, .image)
        let old = try XCTUnwrap(content.old), new = try XCTUnwrap(content.new)
        XCTAssertTrue(old.starts(with: [0x89, 0x50, 0x4E, 0x47]), "valid PNG signature")   // ‰PNG
        XCTAssertTrue(new.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertNotEqual(old, new, "before/after differ so the compare modes show something")
    }

    func test_fixtureAddedImageHasOnlyNew() throws {
        let shot = Fixtures.files.first { $0.path == "assets/screenshot.png" }!
        let diff = try XCTUnwrap(FixtureDiffs.diff(for: shot, context: .workingTree(staged: false)))
        let content = try XCTUnwrap(diff.binaryContent)
        XCTAssertNil(content.old, "an added file has no before")
        XCTAssertNotNil(content.new)
    }

    func test_fixturePDFContent() throws {
        let spec = Fixtures.files.first { $0.path == "docs/spec.pdf" }!
        let diff = try XCTUnwrap(FixtureDiffs.diff(for: spec, context: .workingTree(staged: false)))
        let content = try XCTUnwrap(diff.binaryContent)
        XCTAssertEqual(content.kind, .pdf)
        let old = try XCTUnwrap(content.old)
        XCTAssertTrue(old.starts(with: Array("%PDF".utf8)), "valid PDF header")
    }
}
