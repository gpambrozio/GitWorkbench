# 03 — Views

The component is a vertical stack: **Toolbar** on top, then a horizontal row of **Rail** + the
active workspace body (**Changes**, **History**, or **Stash**). The rail and toolbar persist across
all three views. Metrics referenced here are defined in [04-design-tokens.md](04-design-tokens.md).

Root composition:

```
GitWorkbenchView
└─ VStack(spacing: 0)
   ├─ WorkbenchToolbar            (height 52)        — hidden if config.showsToolbar == false
   └─ HStack(spacing: 0)
      ├─ WorkspaceRail            (width 218)
      └─ Group {
            switch state.activeView {
              case .changes:  ChangesBody
              case .history:  HistoryBody
              case .stashes:  StashBody
            }
         }
```

A `Toast` overlay is aligned `.bottom` on the whole component.

---

## Toolbar — `WorkbenchToolbar`

Single bar, height **52**, material per [04 §4.6]. Three regions left→right:

1. **Repo cluster** (fixed width = railWidth 218, trailing `1px` separator): repository name,
   13pt `.bold`, leading padding 20. (No traffic lights — host owns them.)
2. **Action cluster** (leading padding 14, gap ~3):
   - `Pull` button — icon `arrow.down`, label `"Pull"` + behind count when `behind > 0`
     (e.g. `Pull 1`). Disabled while `isBusy`.
   - `Push` — icon `arrow.up`, label `"Push"` + ahead count when `ahead > 0`.
   - `Fetch` — icon `arrow.triangle.2.circlepath`, label `"Fetch"`.
   - `1px` vertical divider (height 22).
   - **Branch pill** (`BranchPill`): branch glyph (accent) + branch name (12.5pt `.semibold`) +
     `chevron.up.chevron.down` (tertiary). Tap toggles the branch menu.
   - `History` toolbar toggle — icon `clock.arrow.circlepath`; **active** background
     `rgba(0,0,0,0.08)` when `activeView == .history`.
   - `Stash` toolbar toggle — icon `folder`; active when `activeView == .stashes`.
3. **Trailing** (padding 14): unified/split **Segmented** control (icons only: `equal` /
   `rectangle.split.2x1`), bound to `state.diffMode`.

**Toolbar button** spec: height 28, h-padding 10, radius 7, gap 6; idle text `.secondaryLabelColor`,
icon same; `active` fills `rgba(0,0,0,0.08)`. Press animation per [04 §4.5].

### Branch menu — `BranchMenu` (popover)
Anchored under the branch pill, width 280, `.regularMaterial`, radius 11, shadow per [04 §4.4].
- Header row: "SWITCH BRANCH" (11pt `.bold` uppercase tertiary).
- One row per branch: branch glyph + name; **current** branch row is `.semibold`, accent glyph,
  shows `{ahead}↑ {behind}↓` (tertiary, tabular) + a trailing `checkmark` (accent).
- Hover highlights rows `rgba(0,0,0,0.05)`.
- Divider, then a final row: `plus` + "New branch from HEAD…" (secondary).
- Dismiss on outside click / Esc. Selecting a branch calls `store.switchBranch(to:)`, closes the
  menu, and shows a toast "Switched to {branch}".

---

## Rail — `WorkspaceRail`

Width **218**, background `sidebarDeep` (`.underPageBackgroundColor`), vertical scroll. Three
sections, each headed by an 11pt `.bold` uppercase tertiary `SectionHeader` (padding `14,16,5`):

1. **WORKSPACE**
   - `Changes` — icon `doc`, count = total changed files. Selected when `activeView == .changes`.
   - `History` — icon `clock.arrow.circlepath`, count = commits. Selected on `.history`.
   - `Stashes` — icon `folder`, count = stashes. Selected on `.stashes`.
2. **BRANCHES** — one `RailItem(branch:)` per local branch; **current** = `.bold` + accent glyph +
   a small `HEAD` pill (accent on accentSoft) trailing. Tapping a branch switches to it.
3. **REMOTES** — `origin` (folder), and an indented (indent 26) `origin/{branch}` branch row.

**RailItem** spec: height 28, h-margin 8, h-padding 8, radius 6, icon+label gap 8. **Selected**:
accent fill, white text/icon, count text `rgba(255,255,255,0.85)`. Hover (unselected):
`rgba(0,0,0,0.05)`. Count badge: 11pt `.semibold` tabular, tertiary.

---

## Changes view — `ChangesBody`

Two panes after the rail: the **file list + commit composer** (width 320), then the **diff pane**
(fluid, min 420).

### File list pane (`sidebar` background)
Scrollable. Two collapsible groups; render **Staged first**, then **Changes** (unstaged). Hide a
group when empty.

**Group header** (`SectionHeader`, sticky to top of the scroll, background `sidebar`):
`chevron.down` (collapse) + title (11pt `.bold` uppercase) + count badge
(`rgba(0,0,0,0.06)` pill) + spacer + bulk action link.
- Staged group action: "Unstage all" (`accentDeep`, 11pt `.semibold`) → `store.unstageAll()`.
- Changes group action: "Stage all" → `store.stageAll()`.

**File row** (`FileListRow`, height 30, h-padding 12, gap 8):
`[stage box] [status glyph] [name 12.5pt .medium] [directory tertiary, truncates] [spacer] [stats | hover actions]`
- The **stage box** is independently tappable (`onTapGesture` with `.stopPropagation` semantics —
  in SwiftUI, put it in its own button/hit area) → `store.toggleStage(file.id)`.
- Tapping the **row** selects the file → loads its diff.
- **Selected** row: accent fill, white text; directory `rgba(255,255,255,0.7)`; status glyph
  switches to **filled**.
- On **hover**, the trailing `+N −N` stats are replaced by a **discard** icon button
  (`arrow.uturn.backward`, 20×20, `rgba(0,0,0,0.06)` chip; on selected rows `rgba(255,255,255,0.18)`)
  → `store.requestDiscard(file.id)`.
- Directory truncates with a middle-ish ellipsis; the **filename never truncates** before the dir.

**Empty (clean tree):** centered empty state — 44×44 rounded `rgba(0,0,0,0.05)` tile with a green
`checkmark`, "Working tree clean" (13pt `.semibold` secondary), "No changes to commit." (12pt
tertiary).

### Commit composer (`CommitComposer`, docked to bottom of this pane)
Top border `1px sep`, padding 12, background `sidebar`. Never scrolls away.
- **Message field:** `TextEditor`, height 58, padding ~10, radius 8, `field` background, inset
  `1px sep` border; placeholder "Message (⌘↵ to commit)" (tertiary). On focus, border →
  `1.5px accentRing`. Multi-line; first line is the summary.
- **Commit button:** full width, height 30, radius 7. **Enabled** only when `state.canCommit`
  (≥1 staged file **and** non-empty trimmed message): accent fill + white, `checkmark` icon, label
  `Commit {n} file(s) to {branch}`. **Disabled:** `rgba(0,0,0,0.07)` fill, tertiary text.
- **⌘↵** anywhere in the field commits when enabled.
- On commit: `store.commit()` → clears staged group + message, increments ahead, toast
  "Committed {n} files · "{summary}"".

### Diff pane (`winBg` background)
- **Header** (height 44, h-padding 16, bottom `1px sep`):
  `[FileMeta] | [status word] [spacer] [Stage/Unstage button] [Discard button]`
  - `FileMeta` = status glyph + filename (13pt `.semibold`) + dimmed `dir/` + spacer + `+N −N`.
  - Status word = `file.status.label` (e.g. "Modified"), tertiary, after a `1px` divider.
  - Stage/Unstage button reflects current staged state; Discard opens the confirm.
- **Body:** `DiffView(file:mode:)` in a vertical scroll.
- **No selection:** `EmptyState` — 46×46 tile with `doc` icon + "Select a file to view changes"
  (tertiary). When the tree is clean: "Nothing to show — working tree is clean".

### Confirm discard — `ConfirmPopover`
Centered over the diff pane on a `rgba(0,0,0,0.18)` scrim. Card width 360, radius 13, padding ~20,
centered text:
- 44×44 round `delBg` tile with `arrow.uturn.backward` (del color).
- Title: "Discard changes in {name}?" (15pt `.bold`).
- Body: "This will permanently discard {add+del} line change(s). You can't undo this." (12.5pt
  secondary).
- Buttons row: **Cancel** (`rgba(0,0,0,0.07)` fill) + **Discard Changes** (`del` fill, white).
- Confirm → `store.confirmDiscard()` removes the file + toast "Discarded changes in {name}".

---

## History view — `HistoryBody`

Replaces the two Changes panes with a **commit list** (width 360) + **commit detail** (fluid).

### Commit list pane (`sidebar`)
- **Header** (h-padding 14, bottom `1px sep`): `clock.arrow.circlepath` + "HISTORY" + count badge +
  spacer + a small read-only `BranchPill` (height 24) showing the branch.
- **Commit rows** (`CommitGraphRow`), scrollable, newest first:
  - **Graph column** (width 34): a vertical 2px line centered at x≈16 running full height
    (`sepStrong`; clipped to start at 50% on the first row and end at 50% on the last), with a
    **node** — 10×10 circle, `winBg` fill + `0 0 0 2px accent` ring — centered vertically. On a
    **selected** row, line + node go white.
  - **Content** (padding `9,14,9,2`, bottom `1px sep`):
    - Line 1: summary (12.5pt `.semibold`, truncates) + ref **pills** (`CommitRef`): HEAD pill
      (accent), branch pill (blue + branch glyph), tag pill (green + tag glyph). On selected rows,
      pills become white-on-`rgba(255,255,255,0.22)`.
    - Line 2 (gap 5): 15px monogram **Avatar** (hue by author — GA 295, MP 25) + author name (11pt) +
      "· {relativeDate}" (tertiary) + spacer + shortSHA (mono 10.5pt tertiary).
  - **Selected** row: accent fill, white text. Hover (unselected): `rgba(0,0,0,0.04)`.
  - Selecting a commit loads its files and selects the first file's diff.

### Commit detail pane (`winBg`)
Vertical: metadata block → changed-files block → diff.
- **Metadata** (padding `16,20,14`, bottom `1px sep`):
  - Summary 16pt `.bold` (tracking −0.2).
  - Body (if any): mono 12.5pt secondary, preserves line breaks.
  - Row (gap 10, top 14): 26px Avatar + (name `.semibold` + `<email>` tertiary; "committed {date}"
    tertiary) + spacer + a **copy-SHA** button (mono 11.5pt `.semibold`, `rgba(0,0,0,0.06)` chip,
    `doc.on.doc` icon) → toast "Copied {shortSHA} to clipboard".
- **Changed files** (background `#FAFAFB`, bottom `1px sep`): a tiny header "{n} changed file(s)"
  (10.5pt `.bold` uppercase tertiary), then `DetailFileRow`s (height 30, h-padding 16): status glyph
  + name + dir + `+N −N`. **Selected** file row: `accentSoft` background + `inset 2px accent` leading
  bar. Selecting updates the diff below.
- **Diff:** `DiffView(file:mode:)` scroll, fills remaining height.

---

## Stash view — `StashBody`

Mirror of History: **stash list** (width 360) + **stash detail** (fluid). Stash list has local
state so Pop/Drop can remove entries.

### Stash list pane (`sidebar`)
- **Header:** `folder` + "STASHES" + count badge + spacer + a small "Stash" button (`plus`) to
  shelve current changes.
- **Stash rows** (`StashRow`, padding `11,14`, bottom `1px sep`, column gap 5):
  - Line 1: `ref` pill (mono 10.5pt `.bold`, `accentDeep` on `accentSoft`; white-on-translucent when
    selected) + message (12.5pt `.semibold`, truncates).
  - Line 2: branch glyph + branch (11pt) + "· {relativeDate}" + spacer + "{n} file(s)".
  - **Selected:** accent fill, white text. Hover: `rgba(0,0,0,0.04)`.
- **Empty:** centered "No stashes" empty state with `folder` tile + "Shelved changes show up here."

### Stash detail pane (`winBg`)
- **Header** (padding `16,20,14`, bottom `1px sep`):
  - Row 1: `ref` pill (mono) + message (16pt `.bold`).
  - Row 2 (top 10): branch glyph + "on {branch}" + "· stashed {date}" (tertiary) + spacer +
    **action buttons**:
    - **Apply** — `tray.and.arrow.down`, neutral `rgba(0,0,0,0.06)` → `store.applyStash` (keeps the
      stash) + toast "Applied {ref} to working tree".
    - **Pop** — `arrow.up`, **primary** (accent) → `store.popStash` (apply + remove) + toast
      "Popped {ref} — "{message}"".
    - **Drop** — `trash`, **danger** (`delBg` fill, `del` text) → `store.dropStash` (remove) + toast
      "Dropped {ref} — "{message}"".
    - Pop/Drop remove the row and reselect the next stash (or empty state).
- **Changed files:** same `DetailFileRow` block as History (`#FAFAFB`).
- **Diff:** `DiffView(file:mode:)` scroll.

---

## Diff renderer — `DiffView`

`DiffView(file: FileChange or FileDiff, mode: DiffMode)`. Mono 12pt, line height 20. Renders each
hunk as: a **hunk header** band then its lines. Use `LazyVStack` and only realize hunks near the
viewport for large files (show a "Load more" affordance past a threshold).

**Hunk header band:** the hunk's `@@ … @@` text, mono 11.5pt tertiary, padding `5,14`, background
`rgba(124,92,224,0.05)`, `1px sep` top & bottom, no wrap.

### Unified — `UnifiedDiff`
Each line is an `HStack(spacing: 0)`:
`[oldNo gutter w46, right-aligned, pad-r 12, tertiary, non-selectable]`
`[newNo gutter w46, same]`
`[sign column w20, centered, .bold — "+" addInk / "−" delInk / " "]`
`[code, flexible, monospaced, no wrap (allow horizontal scroll), pad-r 16, .labelColor]`
Row background: `addBg` (add) / `delBg` (del) / clear (context). Changed rows get a **leading 3px
edge bar** (`addGut` / `delGut`) via an inset shadow or overlay.

### Split — `SplitDiff`
Derive paired rows from the hunk (see [02 §2.3 split derivation](02-data-model.md)). Each visual row
is two side cells:
`SplitSide` = `[number gutter w40, right-aligned, tertiary] [sign w14] [code, truncates with
ellipsis, no wrap]`.
- Left side shows old numbers; right side shows new numbers.
- Cell background: add `addBg`, del `delBg`, context clear; a **missing counterpart** cell uses the
  empty tint `rgba(0,0,0,0.025)` with transparent text.
- A `1px sep` divider runs between the two sides.

### Deleted file
When `file.status == .deleted`, render the diff as a single fully-removed block (all `del` lines,
unified style) regardless of `mode`, at ~0.92 opacity.

### Binary / image (future-friendly)
If `FileDiff.isBinary`, render a centered before→after metadata row instead of text hunks.

---

## Shared primitives (build in P1)

| View | Spec source |
|---|---|
| `StatusGlyph(status:selected:)` | rounded square, outlined/filled per [04 §4.3] |
| `StageBox(checked:partial:)` | 15×15, accent check / dash |
| `StatChips(add:del:)` | mono tabular, `addInk` / `delInk` |
| `Avatar(initials:size:hue:)` | `oklch(0.62 0.15 hue)` disc, white monogram, inset hairline |
| `BranchPill(name:dim:)` | branch glyph + name + chevron |
| `Segmented(value:options:)` | track + white selected segment |
| `SectionHeader(title:count:action:)` | uppercase header + badge + trailing action |
| `ToolButton(icon:label:active:role:)` | toolbar/diff-header button incl. primary/danger roles |
| `EmptyState(icon:title:subtitle:)` | tile + two-line message |
| `Toast` overlay | dark capsule, spinner for `.progress`, colored glyph otherwise |

Avatar hue→RGB: replicate `oklch(0.62 0.15 H)`. If targeting macOS 14 without OKLCH `Color`,
precompute the two used hues (295 → purple, 25 → warm orange) as literal `Color`s, or convert OKLCH
→ sRGB at build time.
