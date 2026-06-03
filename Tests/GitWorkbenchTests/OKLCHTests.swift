import XCTest
@testable import GitWorkbench

final class OKLCHTests: XCTestCase {
    func test_redAnchorRoundTrips() {
        // sRGB red (1,0,0) ≈ OKLCH(0.6279554, 0.2576833, 29.2338°)
        let (r, g, b) = OKLCH.srgb(l: 0.6279554, c: 0.2576833, h: 29.2338)
        XCTAssertEqual(r, 1.0, accuracy: 0.02)
        XCTAssertEqual(g, 0.0, accuracy: 0.02)
        XCTAssertEqual(b, 0.0, accuracy: 0.02)
    }

    func test_avatarHueFamilies() {
        // GA hue 295 → purple (red & blue dominate green)
        let purple = OKLCH.srgb(l: 0.62, c: 0.15, h: 295)
        XCTAssertGreaterThan(purple.r, purple.g)
        XCTAssertGreaterThan(purple.b, purple.g)
        // MP hue 25 → warm (red > green > blue)
        let warm = OKLCH.srgb(l: 0.62, c: 0.15, h: 25)
        XCTAssertGreaterThan(warm.r, warm.g)
        XCTAssertGreaterThan(warm.g, warm.b)
    }

    func test_componentsClampToUnitRange() {
        let (r, g, b) = OKLCH.srgb(l: 0.62, c: 0.15, h: 295)
        for v in [r, g, b] {
            XCTAssertGreaterThanOrEqual(v, 0.0)
            XCTAssertLessThanOrEqual(v, 1.0)
        }
    }
}
