import Foundation

/// Maps prototype icons to SF Symbol names. Source: 04-design-tokens.md §4.7.
public enum IconLibrary {
    public static let chevronDown = "chevron.down"
    public static let chevronRight = "chevron.right"
    public static let chevronUpDown = "chevron.up.chevron.down"
    public static let plus = "plus"
    public static let minus = "minus"
    public static let check = "checkmark"
    public static let push = "arrow.up"
    public static let pull = "arrow.down"
    public static let fetch = "arrow.triangle.2.circlepath"
    public static let refresh = "arrow.clockwise"
    public static let discard = "arrow.uturn.backward"
    public static let history = "clock.arrow.circlepath"
    public static let file = "doc"
    public static let folder = "folder"
    public static let splitColumns = "rectangle.split.2x1"
    public static let unifiedRows = "equal"

    // Image-comparison controls (issue #12: image/PDF viewing).
    public static let compareSideBySide = "rectangle.split.2x1"
    public static let compareSwipe = "slider.horizontal.below.square.and.square.filled"
    public static let compareFade = "circle.lefthalf.filled"
    public static let axisVertical = "arrow.left.and.right"
    public static let axisHorizontal = "arrow.up.and.down"
    public static let ellipsis = "ellipsis"
    public static let branch = "arrow.triangle.branch"
    public static let tag = "tag"
    public static let trash = "trash"
    public static let copy = "doc.on.doc"
    public static let applyStash = "tray.and.arrow.down"
    public static let stage = "plus.square"

    /// SF Symbol for a commit ref pill.
    public static func symbol(for ref: CommitRef) -> String? {
        switch ref {
        case .head:   return nil       // HEAD pill is text-only
        case .branch: return branch
        case .tag:    return tag
        }
    }
}
