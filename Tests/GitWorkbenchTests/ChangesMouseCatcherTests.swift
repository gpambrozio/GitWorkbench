import XCTest
import AppKit
@testable import GitWorkbench

/// Verifies the Changes-tab mouse catcher's `hitTest` claim policy: it claims *only* right-clicks (a
/// single, independently-routed event), letting left clicks, hover, scroll, and — critically — cursor
/// updates fall through to the SwiftUI row beneath. Double-click is handled by a local event monitor,
/// not `hitTest` (AppKit delivers the second click of a double-click to whoever took the first), so it's
/// verified live in the demo rather than here, per the project's AppKit-is-verified-visually convention.
///
/// `claimsRightClick` reads only the event *type*, never `clickCount` — reading `clickCount` on a
/// non-button event (e.g. the CursorUpdate AppKit routes through `hitTest` during cursor tracking)
/// raises `NSInternalInconsistencyException` and previously crashed the app on launch.
final class ChangesMouseCatcherTests: XCTestCase {

    func test_claimsRightMouseDownOnly() {
        // Only the down is claimed (the handler fires there). The matching up — and everything else —
        // falls through so the row's own responder chain (e.g. a future .contextMenu) stays intact.
        XCTAssertTrue(ChangesMouseCatcher.claimsRightClick(eventType: .rightMouseDown))
        XCTAssertFalse(ChangesMouseCatcher.claimsRightClick(eventType: .rightMouseUp))
    }

    func test_doesNotClaimLeftClicks() {
        // Left clicks (single or double) must fall through: selection and the stage box live beneath, and
        // double-click is caught by the event monitor, not here.
        XCTAssertFalse(ChangesMouseCatcher.claimsRightClick(eventType: .leftMouseDown))
        XCTAssertFalse(ChangesMouseCatcher.claimsRightClick(eventType: .leftMouseUp))
    }

    func test_doesNotClaimCursorUpdateHoverOrScroll() {
        // Regression for the launch crash: these flow through `hitTest`, and claiming them (or reading
        // their clickCount) is exactly what broke. They must all fall through.
        for type: NSEvent.EventType in [.cursorUpdate, .mouseMoved, .mouseEntered, .mouseExited, .scrollWheel] {
            XCTAssertFalse(ChangesMouseCatcher.claimsRightClick(eventType: type),
                           "\(type) should fall through to the row")
        }
    }

    func test_doesNotClaimWhenNoCurrentEvent() {
        XCTAssertFalse(ChangesMouseCatcher.claimsRightClick(eventType: nil))
    }
}
