import SwiftUI
import AppKit

/// A transparent overlay over a Changes-tab file row that reports right-clicks and double-clicks to the
/// host. SwiftUI exposes no hook for right-clicks, and double-click via `onTapGesture(count: 2)` races
/// the row's single-click selection — so, like `HorizontalScrollCatcher`, this drops to AppKit.
///
/// The catcher claims *only* the events it acts on: it inspects the in-flight event in `hitTest` and
/// returns `nil` for single left-clicks, hover tracking, and scrolling, which then fall straight through
/// to the SwiftUI row beneath (selection, the stage-box tap, the hover highlight, and diff scrolling all
/// keep working). Double-clicks and right-clicks return `self` and are handled here.
struct ChangesMouseCatcher: NSViewRepresentable {
    var onRightClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onRightClick = onRightClick
        view.onDoubleClick = onDoubleClick
    }

    final class CatcherView: NSView {
        var onRightClick: (() -> Void)?
        var onDoubleClick: (() -> Void)?

        // Read the event being dispatched and claim only what we handle. The first click of a
        // double-click has clickCount 1 and falls through (so the row still selects); the second has
        // clickCount 2 and is claimed here — matching the familiar "click selects, double-click opens".
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  ChangesMouseCatcher.shouldClaim(event: event,
                                                  handlesRightClick: onRightClick != nil,
                                                  handlesDoubleClick: onDoubleClick != nil)
            else { return nil }
            return self
        }

        override func rightMouseDown(with event: NSEvent) { onRightClick?() }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { onDoubleClick?() }
        }

        // Never steal keyboard focus.
        override var acceptsFirstResponder: Bool { false }
    }

    /// Whether the catcher should claim (handle) a concrete in-flight `NSEvent` — the rest falls through
    /// to the row. This is what `hitTest` calls. It reads `clickCount` via `clickCount(for:)`, which is
    /// safe on every event type: `NSEvent.clickCount` is only valid for mouse-button events, and reading
    /// it on a CursorUpdate / mouseMoved event — which AppKit routes through `hitTest` during its
    /// cursor-tracking cycle — raises `NSInternalInconsistencyException` and crashes the app.
    nonisolated static func shouldClaim(event: NSEvent,
                                        handlesRightClick: Bool, handlesDoubleClick: Bool) -> Bool {
        claims(eventType: event.type, clickCount: clickCount(for: event),
               handlesRightClick: handlesRightClick, handlesDoubleClick: handlesDoubleClick)
    }

    /// `NSEvent.clickCount` is valid only for mouse-button events; reading it on any other type raises.
    /// Returns the real count for button events and 0 for everything else, so callers never touch the
    /// unsafe accessor on a hover / cursor-update / scroll event.
    nonisolated static func clickCount(for event: NSEvent) -> Int {
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return event.clickCount
        default:
            return 0
        }
    }

    /// Whether the catcher should claim (handle) an in-flight event — the rest falls through to the row.
    /// Pulled out of `hitTest` as a pure function so the pass-through policy is unit-testable without a
    /// live window: right-clicks and the *second* click of a double-click are claimed; single clicks,
    /// hover, and scroll are not. Only claims an event for which a handler is actually wired.
    nonisolated static func claims(eventType type: NSEvent.EventType, clickCount: Int,
                                   handlesRightClick: Bool, handlesDoubleClick: Bool) -> Bool {
        switch type {
        case .rightMouseDown, .rightMouseUp:
            return handlesRightClick
        case .leftMouseDown, .leftMouseUp:
            return handlesDoubleClick && clickCount == 2
        default:
            return false
        }
    }
}
