import SwiftUI
import AppKit

/// A transparent overlay over a Changes-tab file row that reports right-clicks and double-clicks to the
/// host. SwiftUI exposes no hook for right-clicks, so — like `HorizontalScrollCatcher` — this drops to
/// AppKit. Right-clicks and double-clicks travel through *different* mechanisms because AppKit routes
/// them differently:
///
/// - **Right-click** is a single, independently hit-tested event, so `hitTest` can claim it: the overlay
///   returns `self` only for right-mouse events and `nil` for everything else, which falls straight
///   through to the SwiftUI row beneath (selection, the stage box, hover, and scroll keep working).
///
/// - **Double-click** can't use `hitTest`. AppKit delivers the *second* click of a double-click to
///   whichever view took the *first* click — and the first click (clickCount 1) intentionally falls
///   through to the SwiftUI row so it can select. So the second click goes to that row, never to this
///   overlay, and `mouseDown` is never sent here. Instead a local event monitor observes every left
///   mouse-down regardless of routing and fires `onDoubleClick` for a clickCount-2 press inside this
///   row's bounds, returning the event un-consumed so single-click selection still runs.
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

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class CatcherView: NSView {
        var onRightClick: (() -> Void)?
        var onDoubleClick: (() -> Void)? {
            didSet { syncDoubleClickMonitor() }
        }
        /// Token for the local left-mouse-down monitor; non-nil only while a double-click handler is wired
        /// and the view is in a window.
        private var monitor: Any?

        // Claim *only* right-clicks. Reads the in-flight event's type — never its `clickCount`, which is
        // invalid for non-button events (a CursorUpdate routed here during cursor tracking) and raises.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard onRightClick != nil,
                  ChangesMouseCatcher.claimsRightClick(eventType: NSApp.currentEvent?.type)
            else { return nil }
            return self
        }

        override func rightMouseDown(with event: NSEvent) { onRightClick?() }

        // Never steal keyboard focus.
        override var acceptsFirstResponder: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            syncDoubleClickMonitor()   // install once we have a window; tear down when removed from one
        }

        private func syncDoubleClickMonitor() {
            let wantsMonitor = onDoubleClick != nil && window != nil
            if wantsMonitor, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                    self?.fireDoubleClickIfInside(event)
                    return event   // never consume — single-click selection beneath must still run
                }
            } else if !wantsMonitor {
                stopMonitoring()
            }
        }

        private func fireDoubleClickIfInside(_ event: NSEvent) {
            guard event.clickCount == 2, let window, event.window === window else { return }
            let local = convert(event.locationInWindow, from: nil)
            if bounds.contains(local) { onDoubleClick?() }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }

    /// Whether `hitTest` should claim an in-flight event for the right-click handler — the rest falls
    /// through to the row. Pure (reads only the event *type*) so the policy is unit-testable without a
    /// live window, and deliberately never touches `clickCount`.
    nonisolated static func claimsRightClick(eventType: NSEvent.EventType?) -> Bool {
        switch eventType {
        case .rightMouseDown, .rightMouseUp:
            return true
        default:
            return false
        }
    }
}
