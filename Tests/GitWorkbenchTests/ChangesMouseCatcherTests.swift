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

    // MARK: - Double-click exclusion policy

    // A typical row: 400×28, with the stage box at the leading edge and a hover discard button trailing.
    private let rowBounds = CGRect(x: 0, y: 0, width: 400, height: 28)
    private let stageBox = CGRect(x: 12, y: 6, width: 15, height: 15)
    private let discard = CGRect(x: 368, y: 4, width: 20, height: 20)

    func test_firesDoubleClick_overRowBody() {
        // The filename / empty middle of the row: nothing excluded there, so the host action fires.
        XCTAssertTrue(ChangesMouseCatcher.firesDoubleClick(at: CGPoint(x: 150, y: 14),
                                                           in: rowBounds, excluding: [stageBox, discard]))
    }

    func test_doesNotFireDoubleClick_overInteractiveSubControls() {
        // Over the stage box or the discard button the host action must NOT fire — those controls own the
        // double-tap (e.g. it would otherwise toggle staging twice *and* open the file).
        XCTAssertFalse(ChangesMouseCatcher.firesDoubleClick(at: CGPoint(x: 19, y: 14),
                                                            in: rowBounds, excluding: [stageBox, discard]))
        XCTAssertFalse(ChangesMouseCatcher.firesDoubleClick(at: CGPoint(x: 378, y: 14),
                                                            in: rowBounds, excluding: [stageBox, discard]))
    }

    func test_doesNotFireDoubleClick_outsideRowBounds() {
        XCTAssertFalse(ChangesMouseCatcher.firesDoubleClick(at: CGPoint(x: 500, y: 14),
                                                            in: rowBounds, excluding: []))
    }

    func test_firesDoubleClick_overRowBody_whenNothingExcluded() {
        // No exclusions reported yet (e.g. before the sub-control frames are measured): still fires inside.
        XCTAssertTrue(ChangesMouseCatcher.firesDoubleClick(at: CGPoint(x: 19, y: 14),
                                                           in: rowBounds, excluding: []))
    }
}
