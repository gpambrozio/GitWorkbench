import CoreGraphics

/// Static layout metrics (points). Source: docs/design_handoff/04-design-tokens.md §4.3.
public enum Tokens {
    // pane sizes
    public static let toolbarHeight: CGFloat = 52
    public static let railWidth: CGFloat = 218
    public static let changesListWidth: CGFloat = 320
    public static let historyListWidth: CGFloat = 360
    public static let minDiffWidth: CGFloat = 420

    // rows
    public static let railRowHeight: CGFloat = 28
    public static let fileRowHeight: CGFloat = 28
    public static let changesRowHeight: CGFloat = 30
    public static let diffLineHeight: CGFloat = 20
    public static let detailFileRowHeight: CGFloat = 30
    public static let diffHeaderHeight: CGFloat = 44

    // diff gutters
    public static let unifiedGutterWidth: CGFloat = 46
    public static let unifiedSignWidth: CGFloat = 20
    public static let splitGutterWidth: CGFloat = 40
    public static let splitSignWidth: CGFloat = 14
    public static let diffEdgeBarWidth: CGFloat = 3

    // radii
    public static let rowRadius: CGFloat = 6
    public static let buttonRadius: CGFloat = 7
    public static let segmentInnerRadius: CGFloat = 6
    public static let segmentOuterRadius: CGFloat = 8
    public static let cardRadius: CGFloat = 13
    public static let popoverRadius: CGFloat = 11
    public static let pillRadius: CGFloat = 4
    public static let glyphRadius: CGFloat = 4

    // status glyph & stage box
    public static let statusGlyphSize: CGFloat = 16
    public static let glyphStroke: CGFloat = 1.25
    public static let stageBoxSize: CGFloat = 15

    // misc
    public static let railInsetH: CGFloat = 8
    /// Horizontal step added per branch-tree depth level (issue #7).
    public static let railIndentStep: CGFloat = 14
    /// Width reserved for a folder row's disclosure chevron; leaf rows pad by this so their icons
    /// line up under the folder icons at the same depth.
    public static let railChevronWidth: CGFloat = 12
    public static let listRowInsetH: CGFloat = 12
    public static let toastBottomInset: CGFloat = 26
}
