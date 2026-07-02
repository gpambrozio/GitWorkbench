import CoreGraphics

/// Pure geometry for the History commit-message / diff resizer.
///
/// The commit-message area is a resizable, scrollable region above the changed-files list and the
/// diff. Dragging the divider grows the diff and shrinks the message (and vice-versa). These rules
/// keep the result sane regardless of the message length, the persisted preference, or the pane size —
/// and are unit-tested, unlike the SwiftUI wiring in `CommitDetail`.
enum MessageResize {
    /// Minimum message height — roughly two lines (summary + one body line + top padding), so the
    /// message never collapses to nothing.
    static let minHeight: CGFloat = 52
    /// The diff area never drops below this, so shrinking… er, *growing* the message can't hide the diff
    /// (and a very long commit body can't push the diff off-screen).
    static let minDiffHeight: CGFloat = 120

    /// The effective height for the message scroll area.
    ///
    /// - Parameters:
    ///   - desired: the user's persisted preference. A very large value (the un-dragged default) means
    ///     "as tall as the content and pane allow".
    ///   - natural: the measured natural height of the message content (summary + body).
    ///   - available: the total height of the detail pane.
    ///   - reserved: the height of everything else in the pane (pinned author row + files list + divider).
    /// - Returns: a height in `[min(minHeight, natural) … min(natural, room-for-min-diff)]`.
    static func height(desired: CGFloat, natural: CGFloat, available: CGFloat, reserved: CGFloat) -> CGFloat {
        // Before layout settles we don't know the pane size yet — just show the content.
        guard available > 0, natural > 0 else { return natural > 0 ? natural : minHeight }
        let floor = min(minHeight, natural)                 // can't shrink below 2 lines (or content, if shorter)
        let room = available - reserved - minDiffHeight      // keep the diff ≥ minDiffHeight
        let ceiling = max(floor, min(natural, room))         // can't grow past content, nor eat the diff
        return min(ceiling, max(floor, desired))
    }
}
