import XCTest
import AppKit
import PDFKit
@testable import GitWorkbench

/// The fixture payloads must be genuinely renderable by the viewers (a valid PDF snapshots poorly in a
/// headless run, so assert parseability directly here rather than relying on a screenshot).
final class FixtureImagesTests: XCTestCase {

    func test_fixturePNGsDecodeToImagesAtExpectedSize() throws {
        let old = try XCTUnwrap(NSImage(data: FixtureImages.bannerOld))
        let new = try XCTUnwrap(NSImage(data: FixtureImages.bannerNew))
        XCTAssertEqual(old.pixelDimensions, CGSize(width: 1280, height: 720))
        XCTAssertEqual(new.pixelDimensions, CGSize(width: 1280, height: 720))
        let shot = try XCTUnwrap(NSImage(data: FixtureImages.screenshotNew))
        XCTAssertEqual(shot.pixelDimensions, CGSize(width: 900, height: 1400))
    }

    func test_fixturePDFsParseWithOnePage() throws {
        let old = try XCTUnwrap(PDFDocument(data: FixtureImages.specOld))
        let new = try XCTUnwrap(PDFDocument(data: FixtureImages.specNew))
        XCTAssertEqual(old.pageCount, 1)
        XCTAssertEqual(new.pageCount, 1)
    }

    func test_fittedSizeScalesDownOversizedPreservingAspectAndNeverUpscales() {
        // Oversized: 2000×1000 into a 500×500 pane → fit width, keep 2:1 aspect.
        XCTAssertEqual(fittedSize(natural: CGSize(width: 2000, height: 1000),
                                  available: CGSize(width: 500, height: 500)),
                       CGSize(width: 500, height: 250))
        // Smaller than the pane: stays at natural size (no upscaling).
        XCTAssertEqual(fittedSize(natural: CGSize(width: 100, height: 80),
                                  available: CGSize(width: 500, height: 500)),
                       CGSize(width: 100, height: 80))
    }
}
