import SwiftUI
import AppKit

/// A transparent overlay that turns horizontal trackpad / mouse-wheel scrolling into a single offset
/// value (used to slide the split diff's two code columns in lock-step), while letting vertical
/// scrolling fall through to the enclosing `ScrollView`. macOS exposes no SwiftUI hook for raw scroll
/// deltas, so this drops to AppKit's `scrollWheel(with:)`.
struct HorizontalScrollCatcher: NSViewRepresentable {
    /// The current offset owned by SwiftUI. Lets this control adopt changes made elsewhere (e.g. by
    /// dragging the scroll bar) so wheel scrolling resumes from there instead of a stale accumulator.
    let offset: CGFloat
    /// Maximum horizontal offset (0 when the longest line already fits — horizontal input is then ignored).
    let maxOffset: CGFloat
    /// Reports the new absolute offset, already clamped to `0...maxOffset`.
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.maxOffset = maxOffset
        view.offset = offset
        view.lastReported = offset
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.maxOffset = maxOffset
        view.onChange = onChange
        // Someone else (the scroll bar, a resize clamp) moved the offset → adopt it.
        if abs(offset - view.lastReported) > 0.01 {
            view.offset = offset
            view.lastReported = offset
        }
        if view.offset > maxOffset { view.offset = maxOffset }   // re-clamp after a window resize
    }

    final class CatcherView: NSView {
        var maxOffset: CGFloat = 0
        var onChange: ((CGFloat) -> Void)?
        /// The accumulated offset is owned here so a burst of events arriving before SwiftUI
        /// re-renders still adds up correctly (the SwiftUI state only mirrors it for rendering).
        var offset: CGFloat = 0
        /// Last value handed to SwiftUI — used to tell our own updates apart from external ones.
        var lastReported: CGFloat = 0

        override func scrollWheel(with event: NSEvent) {
            // Precise (trackpad) deltas are already in points; line-based (mouse wheel) deltas aren't.
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
            let dx = event.scrollingDeltaX * scale
            let dy = event.scrollingDeltaY * scale
            if abs(dx) > abs(dy) && maxOffset > 0 {
                let next = min(maxOffset, max(0, offset - dx))
                if next != offset {
                    offset = next
                    lastReported = next
                    onChange?(next)
                }
                // At the clamp edge we still swallow the horizontal event (no vertical leak).
            } else if let scrollView = enclosingScrollView {
                scrollView.scrollWheel(with: event)   // vertical-dominant → let the outer ScrollView handle it
            } else {
                super.scrollWheel(with: event)
            }
        }

        // Receive scroll events without ever stealing keyboard focus.
        override var acceptsFirstResponder: Bool { false }
    }
}
