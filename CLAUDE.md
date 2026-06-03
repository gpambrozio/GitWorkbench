# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

GitWorkbench is a macOS 15+ / Swift 6 SwiftUI git-changes component (Changes / History / Stash views) distributed as a Swift package, plus a real-`git` provider.

## Commands

Build and test go through the XcodeBuildTools `swift-package` skill — a sandboxing `swift` wrapper is on `PATH`, so call `swift` normally.

- **Build:** `swift build`
- **Test (all):** `swift test` — 100+ tests. The `GitWorkbenchGitKit` integration tests shell out to real `git` (build a temp repo per `setUp`) and spawn many processes, so they're slower than the pure-parser/store tests.
- **Single test:** `swift test --filter DiffSplitterTests` or `swift test --filter CLIGitProviderTests/test_loadStashes`. To run the already-built bundle directly (faster, and lets you wrap a hard timeout when a real-git test might hang): `xcrun xctest -XCTest GitWorkbenchTests.DiffSplitterTests .build/debug/GitWorkbenchPackageTests.xctest`.
- **Verify builds by hand — do not trust the xcsift summary.** `swift build … | xcsift` has reported `status: success / errors: 0` while a real compile error left a **stale binary** in place. After any build, confirm the binary timestamp advanced (`stat -f %Sm .build/arm64-apple-macosx/debug/<exe>`) or grep the raw `swift build 2>&1` for `error:` / `Linking`.
- **Run on a real repo:** `.build/debug/GitWorkbenchLiveDemo /path/to/repo`. It also has a screenshot mode used to visually verify UI: `--shot <out.png> --view changes|history|stashes [--select <path-or-sha>] [--mode unified|split] [--dark] <repo>` drives the store into a state, then captures the window via `NSView.cacheDisplay` (which renders `ScrollView`/`LazyVStack` content — `ImageRenderer` does not). Capturing needs window-server access, so launch it from the Bash tool with `dangerouslyDisableSandbox: true`. `GitWorkbenchDemo` is the same idea but mock-backed (no repo argument).

## Architecture

The package is a **dependency-free SwiftUI "UI + state" component — it never runs `git` itself.** That host boundary is the central design fact; understand it before changing anything.

- **`GitWorkbench`** (library, zero deps) is the component. The host supplies data and performs git operations through `GitWorkbenchProvider` = `GitWorkbenchDataSource` (reads: status/branches/history/stashes/diff) + `GitWorkbenchActionHandler` (stage/unstage/commit/discard/pull/push/fetch/switch/stash apply·pop·drop). See `Sources/GitWorkbench/Provider/GitWorkbenchProvider.swift`. All provider methods are `async` and run off the main actor; models are `Sendable` value-type structs in `Model/`.
- **Unidirectional data flow.** `@MainActor GitWorkbenchStore` (`Store/`) is an `ObservableObject` holding `@Published private(set) var state: WorkbenchState`. Views are a pure function of `state` and hold no business logic; user intents are store methods that **optimistically** mutate `state` and call the provider (rolling back + surfacing a toast on error). `GitWorkbenchView(store:)` is the single public entry point; `.preview` is a mock-backed store.
- **Two providers cross the boundary.** `MockGitProvider` (bundled; fixtures ported from `docs/design_handoff/reference/src/gitdata.js`) powers SwiftUI previews and `GitWorkbenchDemo`. `CLIGitProvider` in **`GitWorkbenchGitKit`** (separate library that depends on `GitWorkbench`) is the real `git`-CLI provider and powers `GitWorkbenchLiveDemo`. GitKit is a **separate target on purpose** so the core stays zero-dependency — UI-only consumers never pull it.
- **GitKit internals.** `GitRunner` shells to `git` via Foundation `Process` (deliberately not swift-subprocess, to stay dependency-free), feeding pure-function parsers in `GitWorkbenchGitKit/Parsers/` (porcelain v2 `-z`, numstat, unified diff via the core `DiffBuilder`, log, for-each-ref, stash). `CLIGitProvider` maps each protocol method to git commands and merges the results.
- **Theming** is injected through the `\.workbenchTheme` SwiftUI environment value; tokens (colors/typography/metrics) live in `Theme/`. The **authoritative** visual and behavioral values are the design handoff in `docs/design_handoff/` (especially `04-design-tokens.md`) and the HTML/JSX prototype under `docs/design_handoff/reference/` — match those rather than approximating.

## Conventions & constraints

- **Zero third-party dependencies is a hard acceptance criterion.** This rules out test/UI helper libraries (e.g. ViewInspector); SwiftUI rendering is verified visually via the demo `--shot`, not unit-tested.
- Swift 6 **language mode v6** is set on every target (`Package.swift`); platform is macOS 15+. New value models should be `Sendable` (and usually `Hashable`/`Identifiable`).
- The specs and step-by-step plans this was built from live in `docs/superpowers/`.

## Known pitfalls (each cost real debugging to find)

- **`LazyVStack` identity is the #1 source of UI bugs here.** Every `ForEach` inside a lazy container needs **globally-unique, stable ids** — non-unique ids render colliding rows *blank* (e.g. per-hunk split-row indices collided across hunks). And when a row's **section or view type changes in place** (split↔unified diff, staged↔unstaged file), lazy in-place diffing leaves a *stale or mixed* render — force a rebuild with a **state-dependent `.id(...)`** (e.g. `.id(mode)`, `.id("\(file.isStaged):\(file.id)")`). These bugs pass the unit tests and `--shot` snapshots; they only surface on live interaction, so exercise toggles/moves in the running demo.
- **`Process.waitUntilExit()` deadlocks on Swift's cooperative executor.** `GitRunner` waits via `terminationHandler` + a continuation, drains stdout/stderr concurrently, and points stdin at `/dev/null`. Don't reintroduce `waitUntilExit()`.
- **Horizontal diff scrolling:** a two-axis `ScrollView` proposes *unbounded* width, so `maxWidth:`/`minWidth:` collapse the code column — set a **concrete** width from a `GeometryReader`, plus a **separate** `.frame(minHeight: geo.height)` to top-align short diffs (a fixed `width:` and `minHeight:` cannot be the same `.frame` call).
- **git-CLI quirks already handled in `CLIGitProvider` — preserve them:** `git stash show` takes *no* pathspec (diff a stash as the commit it is: `git diff <ref>^ <ref> -- <path>`); page history past the root commit with `--skip=1 <sha>`, not `<sha>^`; `--numstat -z` emits a rename as an `add⇥del⇥ \0 old \0 new` triple (key counts by the new path); untracked files need `git diff --no-index /dev/null <path>` to show content.
