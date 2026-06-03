# 04 — Design Tokens (→ Swift)

Exact values pulled from `reference/src/base.jsx` (the `GT` object) and `reference/src/diff.jsx`.
Treat these as authoritative. Implement them as a `WorkbenchTheme` (colors, semantic-aware) plus a
`Tokens` enum (static metrics). Match within ±1px; colors exact unless a semantic system color is
specified.

---

## 4.1 Color

### Strategy
Prefer **`NSColor` semantic colors** so Dark Mode + the user's accent track for free; fall back to
the literal identity hex where no good semantic exists. `WorkbenchTheme.adoptsSystemAccent` toggles
between the system accent and the purple brand identity.

```swift
public struct WorkbenchTheme: Sendable {
    public var adoptsSystemAccent: Bool = false   // false → purple identity below
    public var accent: Color                      // resolved accent
    // surfaces, ink, lines, status, diff tints … (below)
    public static let standard = WorkbenchTheme()  // purple identity
}
```

### Accent (purple identity)
| Token | Hex | Use |
|---|---|---|
| `accent` | `#7C5CE0` | selection fill, primary buttons, active branch, focus ring base |
| `accentDeep` | `#6A49D4` | link text, pressed primary, SHA/stat accents |
| `accentSoft` | `rgba(124,92,224,0.13)` | selected-tint backgrounds, soft pills |
| `accentRing` | `rgba(124,92,224,0.45)` | text-field focus ring |

When `adoptsSystemAccent == true`, set `accent = Color(nsColor: .controlAccentColor)` and derive
`accentSoft = accent.opacity(0.13)`, `accentRing = accent.opacity(0.45)`,
`accentDeep = accent` blended 12% toward black.

### Surfaces → semantic
| Token | Identity hex | Semantic mapping (preferred) |
|---|---|---|
| `winBg` (diff pane / detail) | `#FFFFFF` | `Color(nsColor: .textBackgroundColor)` |
| `sidebar` (file list / stash list) | `#F3F3F5` | `Color(nsColor: .windowBackgroundColor)` |
| `sidebarDeep` (rail) | `#EBEBEE` | `Color(nsColor: .underPageBackgroundColor)` |
| `titlebar` (toolbar) | `#ECECEF` | bar material — see [§4.6](#46-materials) |
| `field` (text field / composer) | `#FFFFFF` | `Color(nsColor: .controlBackgroundColor)` |

### Ink (text)
| Token | Hex | Semantic |
|---|---|---|
| `ink` (primary) | `#1D1D1F` | `.labelColor` |
| `ink2` (secondary) | `#62626A` | `.secondaryLabelColor` |
| `ink3` (tertiary) | `#8E8E96` | `.tertiaryLabelColor` |

### Lines
| Token | Value | Semantic |
|---|---|---|
| `sep` | `rgba(0,0,0,0.09)` | `.separatorColor` |
| `sepStrong` | `rgba(0,0,0,0.14)` | `.separatorColor` (or +contrast) |

### Status colors
| Status | Token | Hex |
|---|---|---|
| Modified `M` | `mod` | `#C8852C` |
| Added `A` | `add` | `#2E9E5B` |
| Deleted `D` | `del` | `#D1453B` |
| Renamed `R` | `ren` | `#2A6FDB` |
| Untracked `U` | `unt` | `#8A8F98` |
| Conflicted `!` | `conflict` | `#D1453B` (orange-red; sort to top) |

### Diff tints
| Token | Value | Use |
|---|---|---|
| `addBg` | `rgba(46,158,91,0.12)` | added line/cell background |
| `addGut` | `rgba(46,158,91,0.20)` | added line 3px edge bar |
| `addInk` | `#1C7A44` | "+N" stat, addition sign |
| `delBg` | `rgba(209,69,59,0.10)` | deleted line/cell background |
| `delGut` | `rgba(209,69,59,0.18)` | deleted line 3px edge bar |
| `delInk` | `#B23A30` | "−N" stat, deletion sign |
| split empty-cell | `rgba(0,0,0,0.025)` | missing counterpart cell |
| hunk header bg | `rgba(124,92,224,0.05)` | hunk header band |

> In Dark Mode, keep the same hues but raise tint alpha ~1.5× and lighten `addInk`/`delInk` so they
> read on the dark text background. Provide a `WorkbenchTheme.dark` resolved variant, or resolve via
> `@Environment(\.colorScheme)`.

---

## 4.2 Typography

System fonts only.

| Role | Font | Size / weight / leading |
|---|---|---|
| UI body / row label | SF Pro Text (`.system`) | 12.5pt / `.medium` |
| Filename (diff header) | SF Pro Text | 13pt / `.semibold` |
| Detail title (commit/stash) | SF Pro Text | 16pt / `.bold`, tracking −0.2 |
| Section header | SF Pro Text | 11pt / `.bold`, UPPERCASE, tracking +0.4 |
| Toolbar button | SF Pro Text | 12.5pt / `.medium` |
| Primary button | SF Pro Text | 13pt / `.semibold` |
| Code / diff lines | SF Mono (`.system(.body, design: .monospaced)`) | 12pt / 20pt line height |
| Line-number gutter | SF Mono | 12pt, `.tertiaryLabelColor` |
| Stats `+N −N` | SF Mono | 11–13pt / `.semibold`, **tabular figures** |
| SHA / ref | SF Mono | 10.5–11.5pt / `.semibold` |

Use `.monospacedDigit()` / tabular figures for all counts (stats, ahead/behind, badges).

---

## 4.3 Spacing & metrics

```swift
public enum Tokens {
    // pane sizes (also in WorkbenchLayout)
    static let toolbarHeight: CGFloat = 52
    static let railWidth: CGFloat = 218
    static let changesListWidth: CGFloat = 320
    static let historyListWidth: CGFloat = 360
    static let minDiffWidth: CGFloat = 420

    // rows
    static let railRowHeight: CGFloat = 28
    static let fileRowHeight: CGFloat = 28      // history/stash list rows ~ content-sized
    static let changesRowHeight: CGFloat = 30
    static let diffLineHeight: CGFloat = 20
    static let detailFileRowHeight: CGFloat = 30
    static let diffHeaderHeight: CGFloat = 44

    // diff gutters
    static let unifiedGutterWidth: CGFloat = 46   // each of 2 number columns
    static let unifiedSignWidth: CGFloat = 20
    static let splitGutterWidth: CGFloat = 40
    static let splitSignWidth: CGFloat = 14
    static let diffEdgeBarWidth: CGFloat = 3      // colored inset bar on changed lines

    // radii
    static let rowRadius: CGFloat = 6
    static let buttonRadius: CGFloat = 7
    static let segmentInnerRadius: CGFloat = 6
    static let segmentOuterRadius: CGFloat = 8
    static let cardRadius: CGFloat = 13
    static let popoverRadius: CGFloat = 11
    static let pillRadius: CGFloat = 4            // tag/ref pills
    static let glyphRadius: CGFloat = 4           // status square / stage box

    // status glyph & stage box
    static let statusGlyphSize: CGFloat = 16      // 15 in dense lists
    static let glyphStroke: CGFloat = 1.25        // inset stroke when outlined
    static let stageBoxSize: CGFloat = 15

    // misc
    static let railInsetH: CGFloat = 8            // row horizontal margin in rail
    static let listRowInsetH: CGFloat = 12
    static let toastBottomInset: CGFloat = 26
}
```

### Component-specific
- **Toolbar:** height 52. Left cluster width = `railWidth` (218) with a trailing `1px` separator;
  holds repo name (13pt `.bold`). Center cluster: Pull / Push / Fetch buttons, `1px` divider, branch
  pill, History, Stash. Trailing: unified/split segmented control. Button height 28, h-padding 10,
  gap ~3.
- **Status glyph:** rounded square; **outlined** (1.25px inset stroke, status color) in lists when
  unselected, **filled** (status color, white letter) when its row is selected.
- **Stage box:** 15×15, radius 4; unchecked = 1.25px inset stroke `sepStrong` on white; checked =
  accent fill + white check; partial = accent fill + white dash.
- **Segmented control:** track `rgba(0,0,0,0.06)`, padding 2, gap 2; selected segment = white fill
  + shadow `0 1px 2px rgba(0,0,0,0.14)`, height 26.
- **Primary button (Commit):** accent fill, white text, radius 7, shadow
  `0 1px 2px rgba(124,92,224,0.4)`; disabled = `rgba(0,0,0,0.07)` fill + `.tertiaryLabelColor` text.
- **Pills (tag/ref):** font 9.5pt `.bold`, radius 4, padding `1px 5px`; HEAD = accent on
  `accentSoft`; branch = `ren` (blue) + branch glyph; tag = `add` (green) + tag glyph.

---

## 4.4 Shadows

| Element | Shadow |
|---|---|
| Selected segment | `0 1px 2px rgba(0,0,0,0.14)` |
| Primary button | `0 1px 2px rgba(124,92,224,0.40)` |
| Branch menu / popover | `0 16px 44px rgba(0,0,0,0.26)` + `0 0 0 0.5px rgba(0,0,0,0.16)` hairline |
| Confirm dialog | `0 18px 50px rgba(0,0,0,0.30)` + `0 0 0 0.5px rgba(0,0,0,0.12)` |
| Toast | `0 8px 30px rgba(0,0,0,0.34)` |
| Avatar | inset `0 0 0 0.5px rgba(0,0,0,0.10)` |

---

## 4.5 Motion

| Interaction | Spec |
|---|---|
| Press (buttons/icons) | scale to 0.94, opacity 0.8, ~0.08s ease |
| Toast in | fade + translateY 8→0, 0.22s ease; auto-dismiss after 2.2s (9s ceiling for in-flight, replaced by result) |
| View switch (Changes/History/Stash) | instant or ≤0.12s cross-fade; no slide |
| Selection highlight | immediate (no animation) |
| Hover backgrounds | ≤0.12s |

Respect **Reduce Motion**: drop the toast translate + any cross-fade; keep opacity.

---

## 4.6 Materials & vibrancy
- **Toolbar:** use a bar material (`.bar` / `.regularMaterial`) tinted toward `titlebar` `#ECECEF`,
  with a `.separatorColor` hairline bottom. In a host with a unified title bar, prefer the system
  toolbar background.
- **Branch menu & popovers:** `.regularMaterial` (≈ `blur(30px) saturate(180%)` in the prototype)
  with the hairline + shadow from §4.4.
- **Toast:** dark translucent capsule — `Color.black.opacity(0.92)` over `.ultraThinMaterial`,
  white text, radius 10.

---

## 4.7 Icons → SF Symbols

The prototype hand-draws icons (`PATHS` in `base.jsx`). Map them to SF Symbols:

| Prototype | SF Symbol |
|---|---|
| chevDown / chevRight | `chevron.down` / `chevron.right` |
| chevUpDown (branch pill) | `chevron.up.chevron.down` |
| plus / minus / check | `plus` / `minus` / `checkmark` |
| arrowUp (push) / arrowDown (pull) | `arrow.up` / `arrow.down` |
| sync / fetch | `arrow.triangle.2.circlepath` |
| refresh | `arrow.clockwise` |
| discard | `arrow.uturn.backward` |
| history | `clock.arrow.circlepath` |
| file / folder | `doc` / `folder` |
| columns / rows (split/unified) | `rectangle.split.2x1` / `equal` (or `list.dash`) |
| ellipsis | `ellipsis` |
| git branch | `arrow.triangle.branch` |
| tag | `tag` |
| trash (drop stash) | `trash` |
| copy (SHA) | `doc.on.doc` |
| tray (apply stash) | `tray.and.arrow.down` |
| stage | `plus.square` (or the stage box itself) |

Use SF Symbols at the weights implied by the prototype strokes (`.regular`/`.medium`). The
traffic-light cluster from the prototype is **not** reproduced (host owns window chrome).
