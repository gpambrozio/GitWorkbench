# GitWorkbench Design-System Primitives Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the reusable, **internal** design-system primitives (StatusGlyph, StageBox, StatChips, Avatar, ToolButton, Segmented, BranchPill, SectionHeader, EmptyState, ToastView) plus a theme-environment seam and a tested OKLCH→sRGB color utility, with a preview gallery.

**Architecture:** Plan 4 of the program (Foundation + Provider + Store on `main`). These are small, focused SwiftUI views driven by props, reading the resolved `WorkbenchTheme` from a new `\.workbenchTheme` environment value (default `.standard`). They are **internal** (the public surface stays `GitWorkbenchView`/store/models per the handoff). They render the design tokens from §04 and the component specs from §03 "Shared primitives". No store wiring and no changes to `GitWorkbenchView` yet — the real chrome/views (later plans) consume these.

**Tech Stack:** Swift 6 (language mode), SwiftPM, macOS 15+, SwiftUI, XCTest. No third-party dependencies.

**Conventions for this plan:**
- Visual values come from `docs/design_handoff/04-design-tokens.md` and `03-views.md` (Shared primitives table). SF Symbol names are in `IconLibrary` (Plan 1).
- Primitives are `struct … : View` with **no `public`** (internal). They read `@Environment(\.workbenchTheme)`.
- TDD only where there's logic (the OKLCH conversion). Views are verified by `swift build` (which compiles `#Preview` blocks) + a manual canvas check.
- For non-ASCII characters in string literals, use Unicode escapes (e.g. `\u{2212}` for the minus sign) to avoid text-transfer parse issues.
- Run commands from the repo root. Execution on a fresh `feat/primitives` branch off `main`.

---

### Task 1: Theme environment + OKLCH color + Avatar

**Files:**
- Create: `Sources/GitWorkbench/Theme/WorkbenchThemeEnvironment.swift`
- Create: `Sources/GitWorkbench/Theme/OKLCH.swift`
- Create: `Sources/GitWorkbench/Views/Shared/Avatar.swift`
- Test: `Tests/GitWorkbenchTests/OKLCHTests.swift`

- [ ] **Step 1: Write the theme environment seam**

`Sources/GitWorkbench/Theme/WorkbenchThemeEnvironment.swift`:

```swift
import SwiftUI

private struct WorkbenchThemeKey: EnvironmentKey {
    static let defaultValue: WorkbenchTheme = .standard
}

extension EnvironmentValues {
    /// The resolved theme injected by the root view; primitives read this.
    var workbenchTheme: WorkbenchTheme {
        get { self[WorkbenchThemeKey.self] }
        set { self[WorkbenchThemeKey.self] = newValue }
    }
}

extension View {
    /// Injects a resolved `WorkbenchTheme` for descendant primitives.
    func workbenchTheme(_ theme: WorkbenchTheme) -> some View {
        environment(\.workbenchTheme, theme)
    }
}
```

- [ ] **Step 2: Write the failing OKLCH test**

`Tests/GitWorkbenchTests/OKLCHTests.swift`:

```swift
import XCTest
@testable import GitWorkbench

final class OKLCHTests: XCTestCase {
    func test_redAnchorRoundTrips() {
        // sRGB red (1,0,0) ≈ OKLCH(0.6279554, 0.2576833, 29.2338°)
        let (r, g, b) = OKLCH.srgb(l: 0.6279554, c: 0.2576833, h: 29.2338)
        XCTAssertEqual(r, 1.0, accuracy: 0.02)
        XCTAssertEqual(g, 0.0, accuracy: 0.02)
        XCTAssertEqual(b, 0.0, accuracy: 0.02)
    }

    func test_avatarHueFamilies() {
        // GA hue 295 → purple (red & blue dominate green)
        let purple = OKLCH.srgb(l: 0.62, c: 0.15, h: 295)
        XCTAssertGreaterThan(purple.r, purple.g)
        XCTAssertGreaterThan(purple.b, purple.g)
        // MP hue 25 → warm (red > green > blue)
        let warm = OKLCH.srgb(l: 0.62, c: 0.15, h: 25)
        XCTAssertGreaterThan(warm.r, warm.g)
        XCTAssertGreaterThan(warm.g, warm.b)
    }

    func test_componentsClampToUnitRange() {
        let (r, g, b) = OKLCH.srgb(l: 0.62, c: 0.15, h: 295)
        for v in [r, g, b] {
            XCTAssertGreaterThanOrEqual(v, 0.0)
            XCTAssertLessThanOrEqual(v, 1.0)
        }
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter OKLCHTests`
Expected: FAIL — `OKLCH` undefined.

- [ ] **Step 4: Write the OKLCH utility**

`Sources/GitWorkbench/Theme/OKLCH.swift`:

```swift
import SwiftUI

/// OKLCH → sRGB conversion (Björn Ottosson's matrices). Used for author avatar discs.
enum OKLCH {
    /// Returns gamma-encoded sRGB components in 0...1 for OKLCH (L in 0...1, C, H in degrees).
    static func srgb(l: Double, c: Double, h: Double) -> (r: Double, g: Double, b: Double) {
        let hr = h * .pi / 180
        let a = c * cos(hr)
        let bb = c * sin(hr)

        // OKLab → LMS (nonlinear), then cube
        let l_ = l + 0.3963377774 * a + 0.2158037573 * bb
        let m_ = l - 0.1055613458 * a - 0.0638541728 * bb
        let s_ = l - 0.0894841775 * a - 1.2914855480 * bb
        let lc = l_ * l_ * l_
        let mc = m_ * m_ * m_
        let sc = s_ * s_ * s_

        // LMS → linear sRGB
        let rl =  4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
        let gl = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
        let bl = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

        return (gamma(rl), gamma(gl), gamma(bl))
    }

    /// Convenience: an sRGB `Color` for the given OKLCH.
    static func color(l: Double, c: Double, h: Double) -> Color {
        let (r, g, b) = srgb(l: l, c: c, h: h)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    private static func gamma(_ x: Double) -> Double {
        let v = max(0, min(1, x))
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter OKLCHTests`
Expected: PASS (all three).

- [ ] **Step 6: Write the Avatar view**

`Sources/GitWorkbench/Views/Shared/Avatar.swift`:

```swift
import SwiftUI

/// A monogram disc, colored by an OKLCH hue (handoff §03: `oklch(0.62 0.15 hue)`).
struct Avatar: View {
    let initials: String
    var size: CGFloat = 26
    var hue: Double

    var body: some View {
        Circle()
            .fill(OKLCH.color(l: 0.62, c: 0.15, h: hue))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5))
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }
}

#Preview("Avatars") {
    HStack(spacing: 12) {
        Avatar(initials: "GA", hue: 295)
        Avatar(initials: "MP", hue: 25)
        Avatar(initials: "GA", size: 40, hue: 295)
    }
    .padding()
}
```

- [ ] **Step 7: Build & commit**

Run: `swift build && swift test`
Expected: build succeeds; all tests (incl. OKLCH) pass.

```bash
git add Sources/GitWorkbench/Theme/WorkbenchThemeEnvironment.swift Sources/GitWorkbench/Theme/OKLCH.swift Sources/GitWorkbench/Views/Shared/Avatar.swift Tests/GitWorkbenchTests/OKLCHTests.swift
git commit -m "Primitives: add theme environment, OKLCH color utility, and Avatar"
```

---

### Task 2: StatusGlyph, StageBox, StatChips

**Files:**
- Create: `Sources/GitWorkbench/Views/Shared/StatusGlyph.swift`
- Create: `Sources/GitWorkbench/Views/Shared/StageBox.swift`
- Create: `Sources/GitWorkbench/Views/Shared/StatChips.swift`

> The three file-row glyphs. Verified by build + preview. Tokens from §04 §4.3.

- [ ] **Step 1: Write `StatusGlyph.swift`**

```swift
import SwiftUI

/// Rounded-square status badge: outlined when unselected, filled (with a white letter) when selected.
struct StatusGlyph: View {
    @Environment(\.workbenchTheme) private var theme
    let status: FileStatus
    var selected: Bool = false
    var size: CGFloat = Tokens.statusGlyphSize

    var body: some View {
        let color = theme.color(for: status)
        RoundedRectangle(cornerRadius: Tokens.glyphRadius, style: .continuous)
            .fill(selected ? color : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.glyphRadius, style: .continuous)
                    .strokeBorder(selected ? .clear : color, lineWidth: Tokens.glyphStroke)
            )
            .overlay(
                Text(status.rawValue)
                    .font(.system(size: size * 0.6, weight: .bold))
                    .foregroundStyle(selected ? Color.white : color)
            )
            .frame(width: size, height: size)
    }
}

#Preview("StatusGlyph") {
    HStack(spacing: 8) {
        ForEach(FileStatus.allCases, id: \.self) { StatusGlyph(status: $0) }
        Divider().frame(height: 20)
        ForEach(FileStatus.allCases, id: \.self) { StatusGlyph(status: $0, selected: true) }
    }
    .padding()
    .background(Color(hex: 0x7C5CE0).opacity(0.5))
}
```

- [ ] **Step 2: Write `StageBox.swift`**

```swift
import SwiftUI

/// 15×15 staging checkbox: empty / accent-check (checked) / accent-dash (partial).
struct StageBox: View {
    @Environment(\.workbenchTheme) private var theme
    var checked: Bool
    var partial: Bool = false

    var body: some View {
        let filled = checked || partial
        RoundedRectangle(cornerRadius: Tokens.glyphRadius, style: .continuous)
            .fill(filled ? theme.accent : theme.field)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.glyphRadius, style: .continuous)
                    .strokeBorder(filled ? .clear : theme.sepStrong, lineWidth: Tokens.glyphStroke)
            )
            .overlay {
                if partial {
                    Image(systemName: IconLibrary.minus).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                } else if checked {
                    Image(systemName: IconLibrary.check).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: Tokens.stageBoxSize, height: Tokens.stageBoxSize)
    }
}

#Preview("StageBox") {
    HStack(spacing: 10) {
        StageBox(checked: false)
        StageBox(checked: true)
        StageBox(checked: false, partial: true)
    }
    .padding()
}
```

- [ ] **Step 3: Write `StatChips.swift`**

```swift
import SwiftUI

/// "+N −N" addition/deletion counts in tabular mono. Hides a side when its count is zero.
struct StatChips: View {
    @Environment(\.workbenchTheme) private var theme
    var additions: Int
    var deletions: Int
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 6) {
            if additions > 0 {
                Text("+\(additions)").foregroundStyle(theme.addInk)
            }
            if deletions > 0 {
                Text("\u{2212}\(deletions)").foregroundStyle(theme.delInk)   // U+2212 MINUS SIGN
            }
        }
        .font(.system(size: size, weight: .semibold).monospacedDigit())
    }
}

#Preview("StatChips") {
    VStack(alignment: .leading) {
        StatChips(additions: 24, deletions: 6)
        StatChips(additions: 31, deletions: 0)
        StatChips(additions: 0, deletions: 18)
    }
    .padding()
}
```

- [ ] **Step 4: Build & commit**

Run: `swift build`
Expected: succeeds.

```bash
git add Sources/GitWorkbench/Views/Shared/StatusGlyph.swift Sources/GitWorkbench/Views/Shared/StageBox.swift Sources/GitWorkbench/Views/Shared/StatChips.swift
git commit -m "Primitives: add StatusGlyph, StageBox, StatChips"
```

---

### Task 3: PressableButtonStyle, ToolButton, Segmented, BranchPill

**Files:**
- Create: `Sources/GitWorkbench/Util/PressableButtonStyle.swift`
- Create: `Sources/GitWorkbench/Views/Shared/ToolButton.swift`
- Create: `Sources/GitWorkbench/Views/Shared/Segmented.swift`
- Create: `Sources/GitWorkbench/Views/Shared/BranchPill.swift`

> Interactive controls. Press animation per §04 §4.5 (scale 0.94, opacity 0.8, ~0.08s).

- [ ] **Step 1: Write `PressableButtonStyle.swift`**

```swift
import SwiftUI

/// Press feedback: scale to 0.94 + 0.8 opacity over ~0.08s (handoff §04 §4.5).
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
```

- [ ] **Step 2: Write `ToolButton.swift`**

```swift
import SwiftUI

/// Toolbar / diff-header button. Roles: normal (idle/active), primary (accent), danger.
struct ToolButton: View {
    enum Role { case normal, primary, danger }

    @Environment(\.workbenchTheme) private var theme
    var icon: String? = nil
    var label: String? = nil
    var active: Bool = false
    var role: Role = .normal
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                if let label { Text(label) }
            }
            .font(.system(size: 12.5, weight: role == .primary ? .semibold : .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(background, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var foreground: Color {
        switch role {
        case .normal:  return theme.ink2
        case .primary: return .white
        case .danger:  return theme.delInk
        }
    }

    private var background: Color {
        switch role {
        case .normal:  return active ? Color.black.opacity(0.08) : .clear
        case .primary: return theme.accent
        case .danger:  return theme.delBg
        }
    }
}

#Preview("ToolButton") {
    HStack(spacing: 8) {
        ToolButton(icon: IconLibrary.pull, label: "Pull") {}
        ToolButton(icon: IconLibrary.history, active: true) {}
        ToolButton(icon: IconLibrary.check, label: "Commit", role: .primary) {}
        ToolButton(icon: IconLibrary.trash, label: "Drop", role: .danger) {}
    }
    .padding()
}
```

- [ ] **Step 3: Write `Segmented.swift`**

```swift
import SwiftUI

/// One option in a `Segmented` control.
struct SegmentedOption<Value: Hashable>: Identifiable {
    var value: Value
    var icon: String? = nil
    var label: String? = nil
    var id: Value { value }
}

/// Track + white selected segment (handoff §04 §4.3). Generic over a `Hashable` value.
struct Segmented<Value: Hashable>: View {
    @Environment(\.workbenchTheme) private var theme
    @Binding var value: Value
    let options: [SegmentedOption<Value>]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option.value == value
                Button { value = option.value } label: {
                    HStack(spacing: 5) {
                        if let icon = option.icon { Image(systemName: icon) }
                        if let label = option.label { Text(label) }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? theme.ink : theme.ink2)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Tokens.segmentInnerRadius, style: .continuous)
                                .fill(.white)
                                .shadow(color: Color.black.opacity(0.14), radius: 1, y: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: Tokens.segmentOuterRadius, style: .continuous))
    }
}

#Preview("Segmented") {
    struct Wrap: View {
        @State var mode: DiffMode = .split
        var body: some View {
            Segmented(value: $mode, options: [
                .init(value: .unified, icon: IconLibrary.unifiedRows),
                .init(value: .split, icon: IconLibrary.splitColumns),
            ])
            .padding()
        }
    }
    return Wrap()
}
```

- [ ] **Step 4: Write `BranchPill.swift`**

```swift
import SwiftUI

/// Branch glyph + name (+ optional chevron). `dim` is the read-only variant.
struct BranchPill: View {
    @Environment(\.workbenchTheme) private var theme
    let name: String
    var dim: Bool = false
    var showsChevron: Bool = true
    var height: CGFloat = 28
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { content }.buttonStyle(PressableButtonStyle())
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 6) {
            Image(systemName: IconLibrary.branch)
                .foregroundStyle(dim ? theme.ink3 : theme.accent)
            Text(name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.ink)
            if showsChevron {
                Image(systemName: IconLibrary.chevronUpDown)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.ink3)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(Color.black.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
    }
}

#Preview("BranchPill") {
    VStack(spacing: 8) {
        BranchPill(name: "feat/auto-sync") {}
        BranchPill(name: "main", dim: true, showsChevron: false, height: 24)
    }
    .padding()
}
```

- [ ] **Step 5: Build & commit**

Run: `swift build`
Expected: succeeds.

```bash
git add Sources/GitWorkbench/Util/PressableButtonStyle.swift Sources/GitWorkbench/Views/Shared/ToolButton.swift Sources/GitWorkbench/Views/Shared/Segmented.swift Sources/GitWorkbench/Views/Shared/BranchPill.swift
git commit -m "Primitives: add ToolButton, Segmented, BranchPill + press style"
```

---

### Task 4: SectionHeader, EmptyState

**Files:**
- Create: `Sources/GitWorkbench/Views/Shared/SectionHeader.swift`
- Create: `Sources/GitWorkbench/Views/Shared/EmptyState.swift`

- [ ] **Step 1: Write `SectionHeader.swift`**

```swift
import SwiftUI

/// Uppercase section header with an optional count badge and a trailing action link.
struct SectionHeader: View {
    @Environment(\.workbenchTheme) private var theme
    let title: String
    var count: Int? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(theme.ink3)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.ink3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.06), in: Capsule())
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accentDeep)
                    .buttonStyle(.plain)
            }
        }
        .padding(.init(top: 5, leading: 14, bottom: 5, trailing: 16))
    }
}

#Preview("SectionHeader") {
    VStack(spacing: 0) {
        SectionHeader(title: "Staged", count: 3, actionTitle: "Unstage all") {}
        SectionHeader(title: "Workspace")
    }
    .padding(.vertical)
}
```

- [ ] **Step 2: Write `EmptyState.swift`**

```swift
import SwiftUI

/// Centered empty-state: a rounded tile with an icon, a title, and an optional subtitle.
struct EmptyState: View {
    @Environment(\.workbenchTheme) private var theme
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconColor: Color? = nil

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.05))
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(iconColor ?? theme.ink3)
                )
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.ink2)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }
}

#Preview("EmptyState") {
    EmptyState(icon: IconLibrary.check, title: "Working tree clean",
               subtitle: "No changes to commit.", iconColor: Color(hex: 0x2E9E5B))
        .frame(width: 300, height: 220)
}
```

- [ ] **Step 3: Build & commit**

Run: `swift build`
Expected: succeeds.

```bash
git add Sources/GitWorkbench/Views/Shared/SectionHeader.swift Sources/GitWorkbench/Views/Shared/EmptyState.swift
git commit -m "Primitives: add SectionHeader and EmptyState"
```

---

### Task 5: ToastView

**Files:**
- Create: `Sources/GitWorkbench/Views/Shared/ToastView.swift`

> Dark translucent capsule (handoff §04 §4.6): `Color.black.opacity(0.92)` over `.ultraThinMaterial`, white text, radius 10, a spinner for `.progress` and a colored glyph otherwise.

- [ ] **Step 1: Write `ToastView.swift`**

```swift
import SwiftUI

/// The toast capsule. A spinner for `.progress`; a colored glyph for success/error/info.
struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            leading
            Text(toast.message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.34), radius: 15, y: 8)
    }

    @ViewBuilder private var leading: some View {
        switch toast.style {
        case .progress:
            ProgressView().controlSize(.small).tint(.white)
        case .success:
            Image(systemName: IconLibrary.check).foregroundStyle(Color(hex: 0x4FBE7C))
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: 0xE36258))
        case .info:
            Image(systemName: "info.circle.fill").foregroundStyle(.white.opacity(0.9))
        }
    }
}

#Preview("ToastView") {
    VStack(spacing: 12) {
        ToastView(toast: .success("Committed 3 files"))
        ToastView(toast: .error("Push rejected \u{2014} pull first"))
        ToastView(toast: .progress("Pushing to origin\u{2026}"))
    }
    .padding(40)
    .background(Color.gray)
}
```

- [ ] **Step 2: Build & commit**

Run: `swift build`
Expected: succeeds.

```bash
git add Sources/GitWorkbench/Views/Shared/ToastView.swift
git commit -m "Primitives: add ToastView capsule"
```

---

### Task 6: Preview gallery

**Files:**
- Create: `Sources/GitWorkbench/Views/Shared/PrimitivesGallery.swift`

> A single internal view that lays out every primitive, with light + dark previews that inject the resolved theme via `.workbenchTheme(_:)`. This is the visual acceptance surface for P1.

- [ ] **Step 1: Write `PrimitivesGallery.swift`**

```swift
import SwiftUI

/// A gallery of every design-system primitive, for visual review.
struct PrimitivesGallery: View {
    @State private var mode: DiffMode = .split

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                row("Status glyphs") {
                    ForEach(FileStatus.allCases, id: \.self) { StatusGlyph(status: $0) }
                    ForEach(FileStatus.allCases, id: \.self) { StatusGlyph(status: $0, selected: true) }
                }
                row("Stage boxes") {
                    StageBox(checked: false); StageBox(checked: true); StageBox(checked: false, partial: true)
                }
                row("Stats") {
                    StatChips(additions: 24, deletions: 6); StatChips(additions: 31, deletions: 0)
                }
                row("Avatars") {
                    Avatar(initials: "GA", hue: 295); Avatar(initials: "MP", hue: 25)
                }
                row("Tool buttons") {
                    ToolButton(icon: IconLibrary.pull, label: "Pull") {}
                    ToolButton(icon: IconLibrary.history, active: true) {}
                    ToolButton(icon: IconLibrary.check, label: "Commit", role: .primary) {}
                    ToolButton(icon: IconLibrary.trash, label: "Drop", role: .danger) {}
                }
                row("Segmented") {
                    Segmented(value: $mode, options: [
                        .init(value: .unified, icon: IconLibrary.unifiedRows),
                        .init(value: .split, icon: IconLibrary.splitColumns),
                    ])
                }
                row("Branch pills") {
                    BranchPill(name: "feat/auto-sync") {}
                    BranchPill(name: "main", dim: true, showsChevron: false, height: 24)
                }
                SectionHeader(title: "Staged", count: 3, actionTitle: "Unstage all") {}
                row("Toasts") {
                    ToastView(toast: .success("Committed 3 files"))
                    ToastView(toast: .progress("Pushing\u{2026}"))
                }
                EmptyState(icon: IconLibrary.file, title: "Select a file to view changes")
                    .frame(height: 160)
            }
            .padding(24)
        }
    }

    @ViewBuilder private func row(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(.secondary)
            HStack(spacing: 12) { content() }
        }
    }
}

#Preview("Gallery — light") {
    PrimitivesGallery()
        .workbenchTheme(.standard)
        .frame(width: 720, height: 760)
        .background(Color(hex: 0xF3F3F5))
}

#Preview("Gallery — dark") {
    PrimitivesGallery()
        .workbenchTheme(.darkStandard)
        .frame(width: 720, height: 760)
        .background(Color(hex: 0x1E1E20))
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build & run the full suite**

Run: `swift build && swift test`
Expected: build succeeds (all `#Preview` blocks compile); all tests pass.

- [ ] **Step 3: Verify the gallery renders**

Open `Package.swift` in Xcode and resume the canvas for `PrimitivesGallery.swift`. Confirm the light and dark galleries show every primitive correctly (glyphs outlined vs filled, stage boxes, stats in green/red, avatars purple/orange, tool buttons in all roles, segmented selection, branch pills, section header with badge + link, toasts with spinner/glyph, empty state). Compare against `reference/Git Workbench Prototype.html`.

- [ ] **Step 4: Commit**

```bash
git add Sources/GitWorkbench/Views/Shared/PrimitivesGallery.swift
git commit -m "Primitives: add preview gallery (light + dark)"
```

---

## Self-Review

**1. Spec coverage (vs. §03 "Shared primitives" table + §04):**
- StatusGlyph, StageBox, StatChips → Task 2 ✓
- Avatar (OKLCH hue) + the tested OKLCH→sRGB utility → Task 1 ✓
- ToolButton (normal/primary/danger + press), Segmented (generic), BranchPill (+ dim) → Task 3 ✓
- SectionHeader (count badge + action), EmptyState → Task 4 ✓
- ToastView (spinner/glyph capsule) → Task 5 ✓
- Theme-environment seam (`\.workbenchTheme` + `.workbenchTheme(_:)`) → Task 1 ✓
- Preview gallery (light + dark) → Task 6 ✓
- **Deferred by design:** the real toolbar/rail/diff/views that *consume* these primitives (later plans); wiring `GitWorkbenchView` to inject `\.workbenchTheme` (when the real views land). Press/Hoverable hover backgrounds beyond the press style are added where rows need them (later plans).

**2. Placeholder scan:** Every view step has complete code; the only "manual" step is the Xcode canvas check in Task 6 (unavoidable for visual verification — `swift build` already proves the previews compile). Non-ASCII glyphs use `\u{…}` escapes.

**3. Type/signature consistency:** `OKLCH.srgb(l:c:h:)`/`.color(l:c:h:)` (Task 1) used by Avatar (Task 1) and tested in `OKLCHTests`. `\.workbenchTheme` (Task 1) read by every primitive. `theme.color(for:)`, `theme.addInk/delInk/accent/ink/ink2/ink3/sepStrong/field/accentDeep/delBg/delInk`, `Tokens.glyphRadius/glyphStroke/stageBoxSize/statusGlyphSize/buttonRadius/segmentInnerRadius/segmentOuterRadius`, `IconLibrary.*`, `FileStatus.allCases/.rawValue`, `Toast.success/.error/.progress`, `DiffMode`, and `Color(hex:)` are all from Plans 1–3 and used consistently. `SegmentedOption`/`Segmented`/`ToolButton.Role`/`PressableButtonStyle` are the new internal types, used by the gallery (Task 6).
