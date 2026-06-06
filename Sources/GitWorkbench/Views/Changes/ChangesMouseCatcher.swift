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
///   overlay, and `mouseDown` is never sent here. Instead a *single, shared* local event monitor
///   (`ChangesDoubleClickMonitor`) observes every left mouse-down regardless of routing and fires
///   `onDoubleClick` for a clickCount-2 press inside this row's bounds, returning the event un-consumed
///   so single-click selection still runs.
///
/// The view is `isFlipped` so its coordinate origin (top-left) matches the SwiftUI frames reported for
/// `doubleClickExclusions` — the interactive sub-controls (stage box / discard button) whose regions a
/// double-click should skip rather than firing the host action on top of the control.
struct ChangesMouseCatcher: NSViewRepresentable {
    var onRightClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    /// Row-local (top-left origin) rects of interactive sub-controls a double-click must not fire over.
    var doubleClickExclusions: [CGRect] = []

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        view.doubleClickExclusions = doubleClickExclusions
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onRightClick = onRightClick
        view.doubleClickExclusions = doubleClickExclusions
        view.onDoubleClick = onDoubleClick
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) {
        view.unregisterDoubleClickMonitor()
    }

    final class CatcherView: NSView {
        var onRightClick: (() -> Void)?
        var onDoubleClick: (() -> Void)? {
            didSet { syncDoubleClickRegistration() }
        }
        /// Row-local (top-left origin, matching `isFlipped`) rects to skip for double-clicks.
        var doubleClickExclusions: [CGRect] = []
        /// Whether this view is currently registered with the shared double-click monitor.
        private var isRegistered = false

        // Match SwiftUI's top-left coordinate origin so `doubleClickExclusions` (measured in the row's
        // SwiftUI coordinate space) line up with the point computed in `fireDoubleClickIfInside`.
        override var isFlipped: Bool { true }

        // Claim *only* right-clicks. Reads the in-flight event's type — never its `clickCount`, which is
        // invalid for non-button events (a CursorUpdate routed here during cursor tracking) and raises.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard onRightClick != nil,
                  ChangesMouseCatcher.claimsRightClick(eventType: NSApp.currentEvent?.type)
            else { return nil }
            return self
        }

        override func rightMouseDown(with event: NSEvent) { onRightClick?() }
        // We claim only the right-mouse *down* (see `claimsRightClick`). AppKit still delivers the matching
        // right-mouse *up* here via mouse capture from the down, and we intentionally don't forward it —
        // nothing downstream consumes a right-mouse-up on these rows today. (A future `.contextMenu` or
        // responder-chain handler on the row would need this overridden and forwarded.)

        // Never steal keyboard focus.
        override var acceptsFirstResponder: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            syncDoubleClickRegistration()   // register once we have a window; deregister when removed from one
        }

        private func syncDoubleClickRegistration() {
            let wantsMonitor = onDoubleClick != nil && window != nil
            if wantsMonitor, !isRegistered {
                ChangesDoubleClickMonitor.shared.add(self)
                isRegistered = true
            } else if !wantsMonitor, isRegistered {
                unregisterDoubleClickMonitor()
            }
        }

        /// Called by the shared monitor for *every* double-click; fires only if the press lands inside this
        /// row and outside its excluded sub-controls. Internal so `ChangesDoubleClickMonitor` can call it.
        func fireDoubleClickIfInside(_ event: NSEvent) {
            guard event.clickCount == 2, let window, event.window === window else { return }
            let local = convert(event.locationInWindow, from: nil)
            if ChangesMouseCatcher.firesDoubleClick(at: local, in: bounds, excluding: doubleClickExclusions) {
                onDoubleClick?()
            }
        }

        func unregisterDoubleClickMonitor() {
            if isRegistered {
                ChangesDoubleClickMonitor.shared.remove(self)
                isRegistered = false
            }
        }
    }

    /// Whether `hitTest` should claim an in-flight event for the right-click handler — the rest falls
    /// through to the row. Claims only the right-mouse *down*: the handler fires there, and leaving the
    /// up (and everything else) unclaimed keeps the row's own responder chain intact. Pure (reads only the
    /// event *type*) so the policy is unit-testable without a live window, and deliberately never touches
    /// `clickCount`.
    nonisolated static func claimsRightClick(eventType: NSEvent.EventType?) -> Bool {
        eventType == .rightMouseDown
    }

    /// Whether a double-click at `point` (row-local, top-left origin) should fire the host action: inside
    /// the row's `bounds` and outside every excluded sub-control rect (the stage box / discard button).
    /// Pure (no event/window) so the exclusion policy is unit-testable without a live window, mirroring
    /// `claimsRightClick`.
    nonisolated static func firesDoubleClick(at point: CGPoint, in bounds: CGRect, excluding exclusions: [CGRect]) -> Bool {
        guard bounds.contains(point) else { return false }
        return !exclusions.contains(where: { $0.contains(point) })
    }
}

/// A single process-wide `.leftMouseDown` monitor shared by every `ChangesMouseCatcher`, rather than one
/// monitor per visible row. AppKit delivers the second click of a double-click to whoever took the first
/// (see `ChangesMouseCatcher`), so a global monitor is the only place that reliably sees every
/// double-click. Funnelling all rows through one monitor keeps it at O(1) monitors and, for the common
/// single-click, O(1) work — the click-count guard returns immediately; only an actual double-click fans
/// out to the registered rows, of which at most one contains the point.
@MainActor
final class ChangesDoubleClickMonitor {
    static let shared = ChangesDoubleClickMonitor()

    private var monitor: Any?
    /// Registered row catchers, weakly held so a recycled/removed row doesn't keep its view alive.
    private let catchers = NSHashTable<ChangesMouseCatcher.CatcherView>.weakObjects()

    private init() {}

    func add(_ catcher: ChangesMouseCatcher.CatcherView) {
        catchers.add(catcher)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.dispatch(event)
            return event   // never consume — single-click selection beneath must still run
        }
    }

    func remove(_ catcher: ChangesMouseCatcher.CatcherView) {
        catchers.remove(catcher)
        guard catchers.allObjects.isEmpty, let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func dispatch(_ event: NSEvent) {
        guard event.clickCount == 2 else { return }   // only a real double-click does any per-row work
        for catcher in catchers.allObjects { catcher.fireDoubleClickIfInside(event) }
    }
}
