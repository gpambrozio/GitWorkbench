# 01 — Architecture: SPM Layout, Public API & Host Integration

> Read alongside [02-data-model.md](02-data-model.md) (the types referenced here).

---

## 1.1 Package layout

```
GitWorkbench/
├── Package.swift
├── README.md
├── Sources/
│   ├── GitWorkbench/                     ← the library product
│   │   ├── GitWorkbenchView.swift        ← public entry view
│   │   ├── Store/
│   │   │   ├── GitWorkbenchStore.swift   ← @MainActor ObservableObject
│   │   │   ├── WorkbenchState.swift      ← value-type state snapshot
│   │   │   └── Toast.swift
│   │   ├── Provider/
│   │   │   ├── GitWorkbenchProvider.swift ← protocols (data + actions)
│   │   │   └── MockGitProvider.swift      ← bundled in-memory mock
│   │   ├── Model/                         ← see 02-data-model.md
│   │   │   ├── FileChange.swift
│   │   │   ├── FileStatus.swift
│   │   │   ├── FileDiff.swift
│   │   │   ├── Commit.swift
│   │   │   ├── Stash.swift
│   │   │   ├── Branch.swift
│   │   │   └── RepositoryStatus.swift
│   │   ├── Views/
│   │   │   ├── Toolbar/WorkbenchToolbar.swift
│   │   │   ├── Rail/WorkspaceRail.swift
│   │   │   ├── Changes/ChangesView.swift
│   │   │   ├── Changes/FileListRow.swift
│   │   │   ├── Changes/CommitComposer.swift
│   │   │   ├── History/HistoryView.swift
│   │   │   ├── History/CommitGraphRow.swift
│   │   │   ├── History/CommitDetail.swift
│   │   │   ├── Stash/StashView.swift
│   │   │   ├── Stash/StashRow.swift
│   │   │   ├── Diff/DiffView.swift
│   │   │   ├── Diff/UnifiedDiff.swift
│   │   │   ├── Diff/SplitDiff.swift
│   │   │   └── Shared/{StatusGlyph,StageBox,StatChips,Avatar,BranchPill,Segmented,SectionHeader,EmptyState,ConfirmPopover}.swift
│   │   ├── Theme/
│   │   │   ├── WorkbenchTheme.swift
│   │   │   ├── Tokens.swift               ← spacing / radius / type scale
│   │   │   └── IconLibrary.swift          ← SF Symbols mapping
│   │   └── Util/{Press,Hoverable}.swift
│   └── GitWorkbenchDemo/                  ← executable demo (optional product)
│       └── DemoApp.swift
└── Tests/
    └── GitWorkbenchTests/
        ├── StoreReducerTests.swift
        ├── DiffSplitterTests.swift
        └── MockProviderTests.swift
```

### Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitWorkbench",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GitWorkbench", targets: ["GitWorkbench"]),
        .executable(name: "GitWorkbenchDemo", targets: ["GitWorkbenchDemo"]),
    ],
    targets: [
        .target(name: "GitWorkbench"),
        .executableTarget(
            name: "GitWorkbenchDemo",
            dependencies: ["GitWorkbench"]
        ),
        .testTarget(
            name: "GitWorkbenchTests",
            dependencies: ["GitWorkbench"]
        ),
    ]
)
```

No external dependencies. SF Symbols only for iconography (see [04 §Icons](04-design-tokens.md)).

---

## 1.2 Public API surface

Keep the public surface small. Everything else is `internal`.

### Entry view

```swift
public struct GitWorkbenchView: View {
    public init(store: GitWorkbenchStore,
                configuration: WorkbenchConfiguration = .init())
    public var body: some View { … }
}
```

### Configuration

```swift
public struct WorkbenchConfiguration: Sendable {
    /// Draw the component's own toolbar bar (default). Set false if the host
    /// projects actions into a native NSToolbar / .toolbar instead.
    public var showsToolbar: Bool = true
    /// Default diff presentation when no per-repo preference is stored.
    public var defaultDiffMode: DiffMode = .split
    /// Which workspace view is shown first.
    public var initialView: WorkspaceView = .changes
    /// Visual theme.
    public var theme: WorkbenchTheme = .standard
    /// Pane sizing (defaults match the spec; see 04).
    public var layout: WorkbenchLayout = .init()

    public init() {}
}

public enum WorkspaceView: String, CaseIterable, Sendable { case changes, history, stashes }
public enum DiffMode: String, Sendable { case unified, split }

public struct WorkbenchLayout: Sendable {
    public var railWidth: CGFloat = 218
    public var changesListWidth: CGFloat = 320
    public var historyListWidth: CGFloat = 360
    public var minRailWidth: CGFloat = 180
    public var minDiffWidth: CGFloat = 420
    public var toolbarHeight: CGFloat = 52
    public init() {}
}
```

### Store

The single source of UI truth. Host creates it with a provider; the view observes it.

```swift
@MainActor
public final class GitWorkbenchStore: ObservableObject {

    public init(provider: GitWorkbenchProvider,
                configuration: WorkbenchConfiguration = .init())

    // Published, read-only to the outside (use `private(set)`):
    @Published public private(set) var state: WorkbenchState

    // Intent methods the views call (each updates state + may call the provider):
    public func select(_ view: WorkspaceView)
    public func select(file: FileChange.ID)
    public func setDiffMode(_ mode: DiffMode)

    public func toggleStage(_ file: FileChange.ID) async
    public func stageAll() async
    public func unstageAll() async
    public func requestDiscard(_ file: FileChange.ID)        // opens confirm
    public func confirmDiscard() async
    public func cancelDiscard()

    public func setCommitMessage(_ text: String)
    public func commit() async                               // guarded: needs staged + message

    public func pull() async
    public func push() async
    public func fetch() async
    public func switchBranch(to branch: Branch) async

    public func selectCommit(_ id: Commit.ID) async
    public func selectStash(_ id: Stash.ID) async
    public func applyStash(_ id: Stash.ID) async
    public func popStash(_ id: Stash.ID) async
    public func dropStash(_ id: Stash.ID) async

    public func reload() async                               // re-pulls status/history/stashes

    // Convenience for previews/demos:
    public static var preview: GitWorkbenchStore { .init(provider: MockGitProvider()) }
}
```

`WorkbenchState` is a value snapshot (see [02-data-model.md §State](02-data-model.md)). Views read
`store.state.…`; they never mutate state directly.

---

## 1.3 Host integration — the provider protocols

The package is UI-only. The host conforms to **`GitWorkbenchProvider`** (a composition of a data
source and an action handler) to feed data and perform real git work. All methods are `async` and
`throws`; the store catches errors and surfaces them as error toasts.

```swift
public protocol GitWorkbenchProvider: GitWorkbenchDataSource, GitWorkbenchActionHandler {}

public protocol GitWorkbenchDataSource: Sendable {
    /// Working-tree status: branch, ahead/behind, staged + unstaged files.
    func loadStatus() async throws -> RepositoryStatus
    /// Commit history for the current branch (newest first). Support paging via `before`.
    func loadHistory(before: Commit.ID?, limit: Int) async throws -> [Commit]
    /// Stash entries (index 0 newest).
    func loadStashes() async throws -> [Stash]
    /// Local branches for the switcher.
    func loadBranches() async throws -> [Branch]
    /// The diff for one file in a given context (working tree, a commit, or a stash).
    func loadDiff(_ request: DiffRequest) async throws -> FileDiff
}

public protocol GitWorkbenchActionHandler: Sendable {
    func stage(_ files: [FileChange]) async throws
    func unstage(_ files: [FileChange]) async throws
    func discard(_ file: FileChange) async throws
    func commit(message: String, staged: [FileChange]) async throws -> Commit

    func pull() async throws -> SyncResult
    func push() async throws -> SyncResult
    func fetch() async throws -> SyncResult
    func switchBranch(to branch: Branch) async throws

    func applyStash(_ stash: Stash) async throws
    func popStash(_ stash: Stash) async throws
    func dropStash(_ stash: Stash) async throws
}

public struct DiffRequest: Sendable {
    public enum Context: Sendable {
        case workingTree(staged: Bool)
        case commit(Commit.ID)
        case stash(Stash.ID)
    }
    public var file: FileChange
    public var context: Context
    public var mode: DiffMode   // host may ignore; renderer can also re-split unified → split
}

public struct SyncResult: Sendable {
    public var ahead: Int
    public var behind: Int
    public var message: String   // e.g. "Pushed 2 commits to origin"
}
```

### Diffing note
The host may return a **unified** `FileDiff` only; the renderer computes the split layout from it
(see `DiffSplitterTests` and [03 §Diff](03-views.md)). So `loadDiff` returning unified hunks is
always sufficient — `mode` is a hint.

### Error handling
Any thrown error becomes a red error toast (`Toast.error(message:)`). The store should map common
cases (e.g. push rejected → "Push rejected — pull first") when the error conforms to
`LocalizedError`; otherwise show `error.localizedDescription`.

---

## 1.4 Threading

- `GitWorkbenchStore` is `@MainActor`. All `@Published` mutations happen on the main actor.
- Provider calls are `await`ed off the main actor (the provider itself is `Sendable`); results are
  applied back on the main actor.
- While a sync (`pull`/`push`/`fetch`) is in flight, set `state.busy = true`, disable the relevant
  toolbar buttons, and show a spinner toast (see [05 §Sync](05-interactions-a11y.md)).

---

## 1.5 Bundled mock provider

`MockGitProvider` returns the fixtures from [02 §Fixtures](02-data-model.md), which mirror
`reference/src/gitdata.js` (repo `aurora-cli`, branch `feat/auto-sync`, 7 changed files, 6 commits,
2 stashes). Its action methods mutate in-memory copies and add small delays
(`try await Task.sleep(for: .milliseconds(700))`) so the in-flight states are demonstrable. This
provider powers `GitWorkbenchStore.preview`, every `#Preview`, the `GitWorkbenchDemo` app, and the
tests.
