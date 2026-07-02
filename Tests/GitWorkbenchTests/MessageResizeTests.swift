import XCTest
@testable import GitWorkbench

/// The pure clamp math behind the History commit-message / diff resizer. The SwiftUI wiring is
/// verified visually (demo `--shot`); this covers the geometry rules that are easy to get wrong.
final class MessageResizeTests: XCTestCase {
    // A comfortably large pane for most cases.
    private let available: CGFloat = 800
    private let reserved: CGFloat = 300   // author row + files list + divider

    func test_shortMessageHugsItsContent() {
        // Message shorter than the 2-line minimum: shown fully, never padded taller than content.
        let h = MessageResize.height(desired: .greatestFiniteMagnitude, natural: 40,
                                     available: available, reserved: reserved)
        XCTAssertEqual(h, 40)
    }

    func test_longMessageUndraggedCapsToKeepMinimumDiff() {
        // Never dragged (sentinel desired) → capped so the diff keeps its minimum height.
        let h = MessageResize.height(desired: .greatestFiniteMagnitude, natural: 500,
                                     available: available, reserved: reserved)
        XCTAssertEqual(h, available - reserved - MessageResize.minDiffHeight)   // 380
        // The diff gets exactly its minimum.
        XCTAssertEqual(available - reserved - h, MessageResize.minDiffHeight)
    }

    func test_userDraggedHeightIsHonoredWithinBounds() {
        let h = MessageResize.height(desired: 120, natural: 500, available: available, reserved: reserved)
        XCTAssertEqual(h, 120)
    }

    func test_cannotShrinkBelowTwoLineMinimum() {
        let h = MessageResize.height(desired: 10, natural: 500, available: available, reserved: reserved)
        XCTAssertEqual(h, MessageResize.minHeight)
    }

    func test_cannotGrowPastNaturalContentHeight() {
        // Desired taller than content, content fits with room to spare → clamp to content (no empty space).
        let h = MessageResize.height(desired: 300, natural: 180, available: available, reserved: reserved)
        XCTAssertEqual(h, 180)
    }

    func test_beforeLayoutSettlesShowsNaturalHeight() {
        // available == 0 (not measured yet): fall back to natural content height.
        let h = MessageResize.height(desired: 200, natural: 140, available: 0, reserved: 0)
        XCTAssertEqual(h, 140)
    }

    func test_tightWindowPinsMessageToMinimum() {
        // Window too small to satisfy min-diff: message stays at the 2-line minimum rather than vanishing.
        let h = MessageResize.height(desired: .greatestFiniteMagnitude, natural: 500,
                                     available: 300, reserved: 250)
        XCTAssertEqual(h, MessageResize.minHeight)
    }
}
