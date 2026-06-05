import XCTest
import AppKit
@testable import GitWorkbench

/// Verifies the pass-through policy of the Changes-tab mouse catcher: it must claim right-clicks and the
/// second click of a double-click, while letting single clicks, hover, and scroll fall through to the
/// row beneath (otherwise selection / the stage-box tap / hover break — exactly the kind of interaction
/// bug `--shot` can't catch). `hitTest` itself reads `NSApp.currentEvent`, so the decision lives in the
/// pure `claims(...)` helper exercised here.
final class ChangesMouseCatcherTests: XCTestCase {

    func test_claimsRightClick_onlyWhenHandlerWired() {
        XCTAssertTrue(ChangesMouseCatcher.claims(eventType: .rightMouseDown, clickCount: 1,
                                                 handlesRightClick: true, handlesDoubleClick: false))
        XCTAssertTrue(ChangesMouseCatcher.claims(eventType: .rightMouseUp, clickCount: 1,
                                                 handlesRightClick: true, handlesDoubleClick: false))
        XCTAssertFalse(ChangesMouseCatcher.claims(eventType: .rightMouseDown, clickCount: 1,
                                                  handlesRightClick: false, handlesDoubleClick: true))
    }

    func test_passesSingleLeftClickThrough() {
        // Single click must fall through so the row's tap-to-select keeps working.
        XCTAssertFalse(ChangesMouseCatcher.claims(eventType: .leftMouseDown, clickCount: 1,
                                                  handlesRightClick: true, handlesDoubleClick: true))
        XCTAssertFalse(ChangesMouseCatcher.claims(eventType: .leftMouseUp, clickCount: 1,
                                                  handlesRightClick: true, handlesDoubleClick: true))
    }

    func test_claimsDoubleClick_onlyWhenHandlerWired() {
        XCTAssertTrue(ChangesMouseCatcher.claims(eventType: .leftMouseDown, clickCount: 2,
                                                 handlesRightClick: false, handlesDoubleClick: true))
        XCTAssertTrue(ChangesMouseCatcher.claims(eventType: .leftMouseUp, clickCount: 2,
                                                 handlesRightClick: false, handlesDoubleClick: true))
        XCTAssertFalse(ChangesMouseCatcher.claims(eventType: .leftMouseDown, clickCount: 2,
                                                  handlesRightClick: true, handlesDoubleClick: false))
    }

    func test_ignoresHoverAndScroll() {
        for type: NSEvent.EventType in [.mouseMoved, .mouseEntered, .mouseExited, .scrollWheel] {
            XCTAssertFalse(ChangesMouseCatcher.claims(eventType: type, clickCount: 0,
                                                      handlesRightClick: true, handlesDoubleClick: true),
                           "\(type) should fall through to the row")
        }
    }
}
