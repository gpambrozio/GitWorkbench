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

    // MARK: - Real NSEvent guard (regression for the CursorUpdate crash)
    //
    // `NSEvent.clickCount` is only valid for mouse-button events; reading it on a CursorUpdate /
    // mouseMoved event raises NSInternalInconsistencyException. AppKit dispatches a CursorUpdate
    // through `hitTest` during its cursor-tracking cycle, so the catcher must decide from a concrete
    // event WITHOUT touching `clickCount` for non-button types. These drive that decision through real
    // NSEvents — the path `hitTest` actually takes.

    func test_doesNotClaimCursorUpdateEvent() throws {
        let cursorUpdate = try XCTUnwrap(
            NSEvent.enterExitEvent(with: .cursorUpdate, location: .zero, modifierFlags: [],
                                   timestamp: 0, windowNumber: 0, context: nil,
                                   eventNumber: 0, trackingNumber: 0, userData: nil))
        // Must not read clickCount on this event (would raise) and must fall through to the row.
        XCTAssertFalse(ChangesMouseCatcher.shouldClaim(event: cursorUpdate,
                                                       handlesRightClick: true, handlesDoubleClick: true))
        XCTAssertEqual(ChangesMouseCatcher.clickCount(for: cursorUpdate), 0)
    }

    func test_claimsRealDoubleClickEvent() throws {
        let doubleClick = try XCTUnwrap(
            NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                               timestamp: 0, windowNumber: 0, context: nil,
                               eventNumber: 0, clickCount: 2, pressure: 1))
        XCTAssertEqual(ChangesMouseCatcher.clickCount(for: doubleClick), 2)
        XCTAssertTrue(ChangesMouseCatcher.shouldClaim(event: doubleClick,
                                                      handlesRightClick: false, handlesDoubleClick: true))
        // Single click falls through so the row still selects.
        let singleClick = try XCTUnwrap(
            NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                               timestamp: 0, windowNumber: 0, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1))
        XCTAssertFalse(ChangesMouseCatcher.shouldClaim(event: singleClick,
                                                       handlesRightClick: false, handlesDoubleClick: true))
    }

    func test_claimsRealRightClickEvent() throws {
        let rightClick = try XCTUnwrap(
            NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                               timestamp: 0, windowNumber: 0, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1))
        XCTAssertTrue(ChangesMouseCatcher.shouldClaim(event: rightClick,
                                                      handlesRightClick: true, handlesDoubleClick: false))
        XCTAssertFalse(ChangesMouseCatcher.shouldClaim(event: rightClick,
                                                       handlesRightClick: false, handlesDoubleClick: false))
    }
}
