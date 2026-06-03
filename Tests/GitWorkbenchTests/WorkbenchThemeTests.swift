import XCTest
import SwiftUI
@testable import GitWorkbench

final class WorkbenchThemeTests: XCTestCase {
    private func rgb(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        return (ns.redComponent, ns.greenComponent, ns.blueComponent)
    }

    func test_standardIsPurpleIdentityAndDoesNotAdoptSystemAccent() {
        let theme = WorkbenchTheme.standard
        XCTAssertFalse(theme.adoptsSystemAccent)
        let c = rgb(theme.accent)
        XCTAssertEqual(c.r, 0x7C / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.g, 0x5C / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.b, 0xE0 / 255.0, accuracy: 0.01)
    }

    func test_systemAccentVariantSetsFlag() {
        let theme = WorkbenchTheme.standard.adoptingSystemAccent()
        XCTAssertTrue(theme.adoptsSystemAccent)
    }

    func test_darkVariantExists() {
        // Dark surfaces differ from light surfaces.
        let light = rgb(WorkbenchTheme.standard.winBg)
        let dark = rgb(WorkbenchTheme.darkStandard.winBg)
        XCTAssertNotEqual(light.r, dark.r, accuracy: 0.0001)
    }
}
