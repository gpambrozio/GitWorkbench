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

    func test_withAccentRecolorsAccentAndLeavesSurfaces() {
        let theme = WorkbenchTheme.standard.withAccent(Color(red: 0.86, green: 0.18, blue: 0.46))
        XCTAssertFalse(theme.adoptsSystemAccent)
        let a = rgb(theme.accent)
        XCTAssertEqual(a.r, 0.86, accuracy: 0.01)
        XCTAssertEqual(a.g, 0.18, accuracy: 0.01)
        XCTAssertEqual(a.b, 0.46, accuracy: 0.01)
        // non-accent tokens untouched
        XCTAssertEqual(rgb(theme.winBg).r, rgb(WorkbenchTheme.standard.winBg).r, accuracy: 0.001)
    }

    func test_publicInitDefaultsUnsetTokensToStandard() {
        let theme = WorkbenchTheme(accent: Color(red: 0.86, green: 0.18, blue: 0.46), winBg: .black)
        XCTAssertEqual(rgb(theme.accent).r, 0.86, accuracy: 0.01)   // overridden
        XCTAssertEqual(rgb(theme.winBg).r, 0, accuracy: 0.01)       // overridden (black)
        // an unset token falls back to the light standard
        let ink = rgb(theme.ink), std = rgb(WorkbenchTheme.standard.ink)
        XCTAssertEqual(ink.r, std.r, accuracy: 0.001)
        XCTAssertEqual(ink.g, std.g, accuracy: 0.001)
        XCTAssertEqual(ink.b, std.b, accuracy: 0.001)
    }
}
