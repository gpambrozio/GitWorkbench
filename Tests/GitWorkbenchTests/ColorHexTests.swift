import XCTest
import SwiftUI
@testable import GitWorkbench

final class ColorHexTests: XCTestCase {
    private func components(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        return (ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent)
    }

    func test_hexParsesToSRGBComponents() {
        let c = components(Color(hex: 0x7C5CE0))
        XCTAssertEqual(c.r, 124.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.g, 92.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.b, 224.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.a, 1.0, accuracy: 0.001)
    }

    func test_hexAppliesOpacity() {
        let c = components(Color(hex: 0x000000, opacity: 0.09))
        XCTAssertEqual(c.a, 0.09, accuracy: 0.001)
    }
}
