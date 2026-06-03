# GitWorkbench — SwiftUI Component Implementation Spec

A handoff package for implementing the **Git Workbench** — a three-pane git-changes UI — as a
reusable **SwiftUI component distributed via Swift Package Manager**.

This document set is written to be fed to **Claude Code** to drive and manage the implementation.
Read this README first, then work through the numbered specs in order.

---

## 0. TL;DR for the implementing agent

You are building a **Swift package** named `GitWorkbench` that exposes a single SwiftUI view,
`GitWorkbenchView`, which any macOS app can drop in to show & operate on a repository's git state.
It has three switchable workspace views — **Changes**, **History**, **Stash** — sharing a left
**rail** and a top **toolbar**.

- **Target:** macOS 15+ (Sequoia), SwiftUI, Swift 6+.
- **Shape:** The package is **pure UI + state**. It does *not* shell out to `git`. The host app
  supplies data and performs git operations through two protocols (`GitWorkbenchDataSource`,
  `GitWorkbenchActionHandler`). The package ships an in-memory **mock provider** (mirroring
  `reference/src/gitdata.js`) so previews and the demo app run with zero host wiring.
- **Source of truth for look & behavior:** the HTML prototype in `reference/`. It is a
  **design reference**, not code to port line-by-line — recreate its appearance and interactions
  idiomatically in SwiftUI.

Build it in the phases listed in [§6 Build plan](#6-build-plan). Each phase is independently
compilable and preview-able.

---

## 1. About the design files in this bundle

```
design_handoff/
├── README.md                      ← you are here (index + build plan)
├── 01-architecture.md             ← SPM layout, public API, host-integration protocols
├── 02-data-model.md               ← Swift data types (the model layer)
├── 03-views.md                    ← the three views, spec'd component-by-component
├── 04-design-tokens.md            ← colors, typography, metrics → Swift
├── 05-interactions-a11y.md        ← interactions, state machine, accessibility, shortcuts, tests
└── reference/
    ├── Git Workbench Prototype.html   ← THE interactive prototype (open in a browser)
    ├── Git Workbench Spec.html        ← human-readable design spec (layout/anatomy/states)
    └── src/                            ← prototype source (read for exact values)
        ├── base.jsx        ← design tokens (GT object) + chrome primitives + icon paths
        ├── diff.jsx        ← unified & split diff renderers + status glyphs
        ├── proto.jsx       ← Changes view + toolbar + rail + store-like state
        ├── proto-views.jsx ← History & Stash views
        └── gitdata.js      ← mock repository data (copy its shape into Swift fixtures)
```

**These HTML/JSX files are design references created as a prototype.** They show the intended
look and behavior. Your job is to **recreate them as a native SwiftUI package** using idiomatic
SwiftUI (no WKWebView, no HTML). When a measurement, color, or behavior is ambiguous in prose,
the prototype source in `reference/src/` is the **authoritative** value — `base.jsx` holds the
exact tokens and `diff.jsx` the exact diff layout.

To see it run: open `reference/Git Workbench Prototype.html` in any browser. Toggle the
unified/split control top-right; click **History** and **Stash** in the toolbar or rail.

---

## 2. Fidelity

**High-fidelity.** The prototype is pixel-considered: final colors, typography, spacing, and
interactions. Recreate the UI faithfully. Where SwiftUI idiom diverges from the HTML
implementation detail (e.g. use a real `TextEditor` instead of a styled `<div>`, real
`.regularMaterial` vibrancy instead of a translucent fill), **prefer the native idiom** while
preserving the visual result and the metrics in [§04](04-design-tokens.md).

---

## 3. What the component is (and is not)

| Is | Is not |
|---|---|
| A self-contained SwiftUI view tree: toolbar + rail + the active workspace view | A window. The **host** owns the `NSWindow` / `WindowGroup`; the component draws no traffic lights or title bar. |
| The staging / review / history / stash **UI** and its local interaction state | A git engine. It never runs `git`; it asks the host via protocols. |
| Themeable (accent + light/dark via system semantics) | Opinionated about the host's data layer — it accepts plain value types. |
| Async-aware (loading, in-flight sync, error toasts) | Networked. All async work is delegated to the host. |

> The prototype draws fake traffic lights only because it renders in a browser. **Do not** draw
> window chrome in the package — the first child is the **toolbar bar** described in
> [03-views.md §Toolbar](03-views.md). Provide a `showsToolbar` config flag for hosts that prefer
> to project actions into a native `.toolbar` instead.

---

## 4. Primary use case

```swift
import SwiftUI
import GitWorkbench

struct RepoWindow: View {
    @StateObject private var store: GitWorkbenchStore

    init(provider: MyGitProvider) {
        // MyGitProvider conforms to GitWorkbenchProvider (data + actions).
        _store = StateObject(wrappedValue: GitWorkbenchStore(provider: provider))
    }

    var body: some View {
        GitWorkbenchView(store: store)
            .frame(minWidth: 900, minHeight: 560)
    }
}
```

Zero-config demo (uses the bundled mock, mirrors the prototype exactly):

```swift
GitWorkbenchView(store: .preview)   // .preview is backed by MockGitProvider
```

Full public API is specified in [01-architecture.md](01-architecture.md).

---

## 5. Acceptance criteria

The implementation is done when:

1. `swift build` and `swift test` pass; the package has **no external dependencies**.
2. `GitWorkbenchView(store: .preview)` renders all three views and every interaction in
   [05-interactions-a11y.md](05-interactions-a11y.md) works against the mock provider.
3. The Changes view supports: select file, stage/unstage (row checkbox + diff-header button),
   stage-all / unstage-all, discard (with confirm), edit commit message, commit (button + ⌘↵),
   branch switch (menu), pull/push/fetch (in-flight + result toasts), unified⇄split toggle.
4. History view: commit list with graph + tag/branch pills, commit detail (message, author,
   date, copyable SHA), per-commit changed-files list, per-file diff.
5. Stash view: stash list, stash detail with **Apply / Pop / Drop**, per-file diff.
6. Visuals match [04-design-tokens.md](04-design-tokens.md) within ±1px; colors are exact.
7. Light & Dark Mode both render correctly; the component adopts `NSColor.controlAccentColor`
   when `theme.adoptsSystemAccent == true`, otherwise the purple identity (`#7C5CE0`).
8. VoiceOver can traverse the file list, diff, and all controls; keyboard shortcuts work.
9. A `Demo` executable target launches a window hosting the component with the mock provider.

---

## 6. Build plan

Implement in phases; keep each phase green (compiles + previews) before moving on.

| Phase | Deliverable | Spec |
|---|---|---|
| **P0 — Scaffold** | `Package.swift`, target layout, `WorkbenchTheme`, `Tokens` enum, mock data fixtures, empty `GitWorkbenchView` shell rendering toolbar + rail + empty body. | 01, 04 |
| **P1 — Design system** | Reusable primitives: `StatusGlyph`, `StageBox`, `StatChips`, `ToolButton`, `BranchPill`, `Segmented`, `Avatar`, `SectionHeader`, `IconLibrary` (SF Symbols mapping). Preview gallery. | 03, 04 |
| **P2 — Diff renderer** | `DiffView(file:mode:)` — unified + split, hunk headers, gutters, sign column, add/del tinting, deleted-file mode. Lazy rows for large diffs. | 03 (Diff), 02 |
| **P3 — Changes view** | Rail + grouped file list (Staged/Changes) + commit composer + diff pane; all local interactions wired to the store. | 03, 05 |
| **P4 — History view** | Commit-graph list + commit detail + changed-files + diff. | 03, 05 |
| **P5 — Stash view** | Stash list + detail + Apply/Pop/Drop + diff. | 03, 05 |
| **P6 — Store & provider** | `GitWorkbenchStore` (@MainActor ObservableObject), `GitWorkbenchProvider` protocol(s), `MockGitProvider`, async actions, toast + busy state, error handling. | 01, 02, 05 |
| **P7 — A11y & keys** | VoiceOver labels/traits, focus order, keyboard shortcuts, reduced-motion. | 05 |
| **P8 — Demo & tests** | `Demo` executable target; unit tests for the store reducer + diff splitter; snapshot-ish preview checks. | 01, 05 |
| **P9 — Polish** | Vibrancy popovers, press/hover states, animations (durations in 04), empty/edge states, docs (`DocC` optional). | 03, 04, 05 |

---

## 7. Conventions for the implementing agent

- **Match the metrics.** Pull exact spacing/sizes from [04-design-tokens.md](04-design-tokens.md)
  (and `reference/src/base.jsx` if in doubt). Don't approximate.
- **Semantic color first.** Map surfaces to `NSColor` semantics (`windowBackgroundColor`,
  `controlBackgroundColor`, `separatorColor`, `controlAccentColor`) so Dark Mode + the user's
  accent track automatically; fall back to the literal hex identity only where no good semantic
  exists. See [04 §Color](04-design-tokens.md).
- **Value types in, closures/protocols out.** Models are `Sendable` structs; the host integrates
  through protocols, never by subclassing views.
- **No business logic in views.** All mutations flow through `GitWorkbenchStore`. Views are a
  function of store state.
- **Previewable everything.** Every view gets a `#Preview` using the mock provider.
- **Don't ship the HTML.** It is reference only.

When unsure about a behavior, open the prototype and the relevant `reference/src/*.jsx` file and
match it.
