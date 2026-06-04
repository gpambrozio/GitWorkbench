import SwiftUI

/// Resolved color set. `.standard` is the light purple identity; `.darkStandard`
/// is the dark variant. Source: docs/design_handoff/04-design-tokens.md §4.1.
public struct WorkbenchTheme: Sendable {
    public var adoptsSystemAccent: Bool

    // accent family
    public var accent: Color
    public var accentDeep: Color
    public var accentSoft: Color
    public var accentRing: Color

    // surfaces
    public var winBg: Color
    public var sidebar: Color
    public var sidebarDeep: Color
    public var titlebar: Color
    public var field: Color

    // ink
    public var ink: Color
    public var ink2: Color
    public var ink3: Color

    // lines
    public var sep: Color
    public var sepStrong: Color

    // status
    public var statusModified: Color
    public var statusAdded: Color
    public var statusDeleted: Color
    public var statusRenamed: Color
    public var statusUntracked: Color
    public var statusConflicted: Color

    // diff tints
    public var addBg: Color
    public var addGut: Color
    public var addInk: Color
    public var delBg: Color
    public var delGut: Color
    public var delInk: Color
    public var splitEmptyCell: Color
    public var hunkHeaderBg: Color

    /// Build a custom theme. Every token defaults to the light identity (`.standard`), so a host can
    /// override only what it wants — e.g. `WorkbenchTheme(accent: .pink, winBg: .black)`. For a dark
    /// variant, start from `.darkStandard` and copy-and-tweak, or pass it as `configuration.darkTheme`.
    public init(
        adoptsSystemAccent: Bool = false,
        accent: Color = Self.standard.accent,
        accentDeep: Color = Self.standard.accentDeep,
        accentSoft: Color = Self.standard.accentSoft,
        accentRing: Color = Self.standard.accentRing,
        winBg: Color = Self.standard.winBg,
        sidebar: Color = Self.standard.sidebar,
        sidebarDeep: Color = Self.standard.sidebarDeep,
        titlebar: Color = Self.standard.titlebar,
        field: Color = Self.standard.field,
        ink: Color = Self.standard.ink,
        ink2: Color = Self.standard.ink2,
        ink3: Color = Self.standard.ink3,
        sep: Color = Self.standard.sep,
        sepStrong: Color = Self.standard.sepStrong,
        statusModified: Color = Self.standard.statusModified,
        statusAdded: Color = Self.standard.statusAdded,
        statusDeleted: Color = Self.standard.statusDeleted,
        statusRenamed: Color = Self.standard.statusRenamed,
        statusUntracked: Color = Self.standard.statusUntracked,
        statusConflicted: Color = Self.standard.statusConflicted,
        addBg: Color = Self.standard.addBg,
        addGut: Color = Self.standard.addGut,
        addInk: Color = Self.standard.addInk,
        delBg: Color = Self.standard.delBg,
        delGut: Color = Self.standard.delGut,
        delInk: Color = Self.standard.delInk,
        splitEmptyCell: Color = Self.standard.splitEmptyCell,
        hunkHeaderBg: Color = Self.standard.hunkHeaderBg
    ) {
        self.adoptsSystemAccent = adoptsSystemAccent
        self.accent = accent; self.accentDeep = accentDeep; self.accentSoft = accentSoft; self.accentRing = accentRing
        self.winBg = winBg; self.sidebar = sidebar; self.sidebarDeep = sidebarDeep; self.titlebar = titlebar; self.field = field
        self.ink = ink; self.ink2 = ink2; self.ink3 = ink3
        self.sep = sep; self.sepStrong = sepStrong
        self.statusModified = statusModified; self.statusAdded = statusAdded; self.statusDeleted = statusDeleted
        self.statusRenamed = statusRenamed; self.statusUntracked = statusUntracked; self.statusConflicted = statusConflicted
        self.addBg = addBg; self.addGut = addGut; self.addInk = addInk
        self.delBg = delBg; self.delGut = delGut; self.delInk = delInk
        self.splitEmptyCell = splitEmptyCell; self.hunkHeaderBg = hunkHeaderBg
    }

    /// Color for a given file status.
    public func color(for status: FileStatus) -> Color {
        switch status {
        case .modified:   return statusModified
        case .added:      return statusAdded
        case .deleted:    return statusDeleted
        case .renamed:    return statusRenamed
        case .untracked:  return statusUntracked
        case .conflicted: return statusConflicted
        }
    }

    /// Returns a copy recolored to `color`, deriving the soft/ring/deep variants from it. Handy for a
    /// quick rebrand: `WorkbenchTheme.standard.withAccent(.pink)`.
    public func withAccent(_ color: Color) -> WorkbenchTheme {
        var copy = self
        copy.adoptsSystemAccent = false
        copy.accent = color
        copy.accentSoft = color.opacity(0.13)
        copy.accentRing = color.opacity(0.45)
        copy.accentDeep = color               // blended-toward-black handled at use sites if needed
        return copy
    }

    /// Returns a copy that uses the macOS system accent (`NSColor.controlAccentColor`).
    public func adoptingSystemAccent() -> WorkbenchTheme {
        var copy = withAccent(Color(nsColor: .controlAccentColor))
        copy.adoptsSystemAccent = true
        return copy
    }

    /// Light purple identity (default).
    public static let standard = WorkbenchTheme(
        adoptsSystemAccent: false,
        accent: Color(hex: 0x7C5CE0),
        accentDeep: Color(hex: 0x6A49D4),
        accentSoft: Color(hex: 0x7C5CE0, opacity: 0.13),
        accentRing: Color(hex: 0x7C5CE0, opacity: 0.45),
        winBg: Color(hex: 0xFFFFFF),
        sidebar: Color(hex: 0xF3F3F5),
        sidebarDeep: Color(hex: 0xEBEBEE),
        titlebar: Color(hex: 0xECECEF),
        field: Color(hex: 0xFFFFFF),
        ink: Color(hex: 0x1D1D1F),
        ink2: Color(hex: 0x62626A),
        ink3: Color(hex: 0x8E8E96),
        sep: Color(hex: 0x000000, opacity: 0.09),
        sepStrong: Color(hex: 0x000000, opacity: 0.14),
        statusModified: Color(hex: 0xC8852C),
        statusAdded: Color(hex: 0x2E9E5B),
        statusDeleted: Color(hex: 0xD1453B),
        statusRenamed: Color(hex: 0x2A6FDB),
        statusUntracked: Color(hex: 0x8A8F98),
        statusConflicted: Color(hex: 0xD1453B),
        addBg: Color(hex: 0x2E9E5B, opacity: 0.12),
        addGut: Color(hex: 0x2E9E5B, opacity: 0.20),
        addInk: Color(hex: 0x1C7A44),
        delBg: Color(hex: 0xD1453B, opacity: 0.10),
        delGut: Color(hex: 0xD1453B, opacity: 0.18),
        delInk: Color(hex: 0xB23A30),
        splitEmptyCell: Color(hex: 0x000000, opacity: 0.025),
        hunkHeaderBg: Color(hex: 0x7C5CE0, opacity: 0.05)
    )

    /// Dark identity variant: same hues, raised tint alpha (~1.5×), lighter add/del ink,
    /// inverted neutral surfaces/ink (§4.1 dark-mode note).
    public static let darkStandard = WorkbenchTheme(
        adoptsSystemAccent: false,
        accent: Color(hex: 0x7C5CE0),
        accentDeep: Color(hex: 0x8B6CF0),
        accentSoft: Color(hex: 0x7C5CE0, opacity: 0.22),
        accentRing: Color(hex: 0x7C5CE0, opacity: 0.55),
        winBg: Color(hex: 0x1E1E20),
        sidebar: Color(hex: 0x252528),
        sidebarDeep: Color(hex: 0x2B2B2F),
        titlebar: Color(hex: 0x2A2A2E),
        field: Color(hex: 0x2C2C30),
        ink: Color(hex: 0xF2F2F4),
        ink2: Color(hex: 0xB6B6BE),
        ink3: Color(hex: 0x86868E),
        sep: Color(hex: 0xFFFFFF, opacity: 0.10),
        sepStrong: Color(hex: 0xFFFFFF, opacity: 0.16),
        statusModified: Color(hex: 0xE0A552),
        statusAdded: Color(hex: 0x4FBE7C),
        statusDeleted: Color(hex: 0xE36258),
        statusRenamed: Color(hex: 0x4F8FF0),
        statusUntracked: Color(hex: 0x9AA0A8),
        statusConflicted: Color(hex: 0xE36258),
        addBg: Color(hex: 0x2E9E5B, opacity: 0.20),
        addGut: Color(hex: 0x2E9E5B, opacity: 0.32),
        addInk: Color(hex: 0x67D08F),
        delBg: Color(hex: 0xD1453B, opacity: 0.18),
        delGut: Color(hex: 0xD1453B, opacity: 0.30),
        delInk: Color(hex: 0xEE7C72),
        splitEmptyCell: Color(hex: 0xFFFFFF, opacity: 0.04),
        hunkHeaderBg: Color(hex: 0x7C5CE0, opacity: 0.12)
    )

    /// Resolves the right variant for a color scheme, preserving the accent choice.
    public static func resolved(for scheme: ColorScheme, adoptsSystemAccent: Bool) -> WorkbenchTheme {
        let base = scheme == .dark ? darkStandard : standard
        return adoptsSystemAccent ? base.adoptingSystemAccent() : base
    }
}
