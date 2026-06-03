# GitWorkbench Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the dependency-free `GitWorkbench` Swift package with its complete value-type data model, design tokens/theme/icon mapping, mock fixtures mirroring the prototype, and an empty workbench shell that builds and previews.

**Architecture:** This is Plan 1 of the GitWorkbench program (see `docs/superpowers/specs/2026-06-02-gitworkbench-design.md`). It builds only the **core package at the repo root** with **zero external dependencies**. Everything here is pure value types + SwiftUI scaffolding — no store, no provider logic, no real diff rendering yet (those are later plans). The deliverable is a package that compiles, has unit-tested model/derivation logic, and renders a skeleton toolbar + rail + empty body in Xcode previews.

**Tech Stack:** Swift 6 (language mode), SwiftPM (`swift-tools-version: 6.0`), SwiftUI, macOS 15+. Test framework: XCTest. No third-party dependencies.

**Conventions for this plan:**
- All model types are `public`, `Sendable`, `Hashable`, and `Identifiable` only where noted in `docs/design_handoff/02-data-model.md`.
- Pure data structs (no behavior) are verified by a compile/build step rather than a contrived unit test; types with real logic (path derivation, status labels, derived state, hex parsing, fixture integrity) get TDD cycles.
- Exact color/metric values come from `docs/design_handoff/04-design-tokens.md`; exact fixture values come from `docs/design_handoff/reference/src/gitdata.js`.
- Run every command from the repo root (`/Users/gustavoambrozio/Development/GitWorkbench`).

---

### Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/GitWorkbench/GitWorkbench.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitWorkbench",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GitWorkbench", targets: ["GitWorkbench"]),
    ],
    targets: [
        .target(
            name: "GitWorkbench",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GitWorkbenchTests",
            dependencies: ["GitWorkbench"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
```

> The `GitWorkbenchDemo` executable target from the handoff is added in the later demo plan. `GitWorkbenchGitKit` is a separate package (later plan). The package stays dependency-free.

- [ ] **Step 2: Create a placeholder source so the target compiles**

`Sources/GitWorkbench/GitWorkbench.swift`:

```swift
// GitWorkbench — a reusable SwiftUI git-changes component.
// Public entry points live in GitWorkbenchView.swift; this file marks the module.

import Foundation

/// Package version marker (informational).
public enum GitWorkbenchInfo {
    public static let version = "0.1.0"
}
```

- [ ] **Step 3: Create the test target directory with a smoke test**

`Tests/GitWorkbenchTests/SmokeTests.swift`:

```swift
import XCTest
@testable import GitWorkbench

final class SmokeTests: XCTestCase {
    func test_moduleLoads() {
        XCTAssertEqual(GitWorkbenchInfo.version, "0.1.0")
    }
}
```

- [ ] **Step 4: Build and test**

Run: `swift build && swift test`
Expected: build succeeds; `test_moduleLoads` passes.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "P0: scaffold GitWorkbench package (macOS 15, Swift 6, zero deps)"
```

---

### Task 2: `Color(hex:)` utility

**Files:**
- Create: `Sources/GitWorkbench/Theme/ColorHex.swift`
- Test: `Tests/GitWorkbenchTests/ColorHexTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/GitWorkbenchTests/ColorHexTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import GitWorkbench

final class ColorHexTests: XCTestCase {
    private func components(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        return (ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent)
    }

    func test_hexParsesToSRGBComponents() {
        let c = components(Color(hex: 0x7C5CE0))
        XCTAssertEqual(c.r, 124.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.g, 92.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.b, 224.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.a, 1.0, accuracy: 0.001)
    }

    func test_hexAppliesOpacity() {
        let c = components(Color(hex: 0x000000, opacity: 0.09))
        XCTAssertEqual(c.a, 0.09, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ColorHexTests`
Expected: FAIL — `Color(hex:)` does not exist (compile error).

- [ ] **Step 3: Write the implementation**

`Sources/GitWorkbench/Theme/ColorHex.swift`:

```swift
import SwiftUI

extension Color {
    /// Builds an sRGB color from a 0xRRGGBB hex value.
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ColorHexTests`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Theme/ColorHex.swift Tests/GitWorkbenchTests/ColorHexTests.swift
git commit -m "P0: add Color(hex:) sRGB utility"
```

---

### Task 3: `FileStatus`

**Files:**
- Create: `Sources/GitWorkbench/Model/FileStatus.swift`
- Test: `Tests/GitWorkbenchTests/FileStatusTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/GitWorkbenchTests/FileStatusTests.swift`:

```swift
import XCTest
@testable import GitWorkbench

final class FileStatusTests: XCTestCase {
    func test_rawValuesMatchGitGlyphs() {
        XCTAssertEqual(FileStatus.modified.rawValue, "M")
        XCTAssertEqual(FileStatus.added.rawValue, "A")
        XCTAssertEqual(FileStatus.deleted.rawValue, "D")
        XCTAssertEqual(FileStatus.renamed.rawValue, "R")
        XCTAssertEqual(FileStatus.untracked.rawValue, "U")
        XCTAssertEqual(FileStatus.conflicted.rawValue, "!")
    }

    func test_longLabels() {
        XCTAssertEqual(FileStatus.modified.label, "Modified")
        XCTAssertEqual(FileStatus.added.label, "Added")
        XCTAssertEqual(FileStatus.deleted.label, "Deleted")
        XCTAssertEqual(FileStatus.renamed.label, "Renamed")
        XCTAssertEqual(FileStatus.untracked.label, "Untracked")
        XCTAssertEqual(FileStatus.conflicted.label, "Conflicted")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FileStatusTests`
Expected: FAIL — `FileStatus` undefined.

- [ ] **Step 3: Write the implementation**

`Sources/GitWorkbench/Model/FileStatus.swift`:

```swift
import Foundation

/// The change kind for one file, mirroring git's status glyphs.
public enum FileStatus: String, Sendable, CaseIterable, Hashable {
    case modified   = "M"
    case added      = "A"
    case deleted    = "D"
    case renamed    = "R"
    case untracked  = "U"
    case conflicted = "!"   // merge conflict; sorts to top in the file list

    /// Long label shown in the diff header.
    public var label: String {
        switch self {
        case .modified:   return "Modified"
        case .added:      return "Added"
        case .deleted:    return "Deleted"
        case .renamed:    return "Renamed"
        case .untracked:  return "Untracked"
        case .conflicted: return "Conflicted"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FileStatusTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Model/FileStatus.swift Tests/GitWorkbenchTests/FileStatusTests.swift
git commit -m "Model: add FileStatus with long labels"
```

---

### Task 4: `FileChange` with path derivation

**Files:**
- Create: `Sources/GitWorkbench/Model/FileChange.swift`
- Test: `Tests/GitWorkbenchTests/FileChangeTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/GitWorkbenchTests/FileChangeTests.swift`:

```swift
import XCTest
@testable import GitWorkbench

final class FileChangeTests: XCTestCase {
    func test_derivesDirectoryAndNameFromNestedPath() {
        let f = FileChange(path: "src/commands/sync.ts", status: .modified,
                           isStaged: true, additions: 24, deletions: 6)
        XCTAssertEqual(f.directory, "src/commands")
        XCTAssertEqual(f.name, "sync.ts")
        XCTAssertEqual(f.id, "src/commands/sync.ts")   // id defaults to the path
    }

    func test_derivesEmptyDirectoryForRootFile() {
        let f = FileChange(path: "package.json", status: .modified,
                           isStaged: false, additions: 3, deletions: 1)
        XCTAssertEqual(f.directory, "")
        XCTAssertEqual(f.name, "package.json")
    }

    func test_explicitIDOverridesPath() {
        let f = FileChange(id: "src/index.ts:staged", path: "src/index.ts",
                           status: .modified, isStaged: true, additions: 8, deletions: 2)
        XCTAssertEqual(f.id, "src/index.ts:staged")
        XCTAssertEqual(f.name, "index.ts")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FileChangeTests`
Expected: FAIL — `FileChange` undefined.

- [ ] **Step 3: Write the implementation**

`Sources/GitWorkbench/Model/FileChange.swift`:

```swift
import Foundation

/// One changed file in the working tree, a commit, or a stash.
public struct FileChange: Identifiable, Hashable, Sendable {
    public var id: String          // stable key; defaults to the repo-relative path
    public var path: String        // "src/commands/sync.ts"
    public var directory: String   // "src/commands" ("" for a root file)
    public var name: String        // "sync.ts"
    public var status: FileStatus
    public var isStaged: Bool       // only meaningful in working-tree context
    public var additions: Int
    public var deletions: Int

    /// Designated initializer. `directory`/`name` are derived from `path` unless given.
    public init(
        id: String? = nil,
        path: String,
        status: FileStatus,
        isStaged: Bool = false,
        additions: Int = 0,
        deletions: Int = 0
    ) {
        self.id = id ?? path
        self.path = path
        let slash = path.lastIndex(of: "/")
        if let slash {
            self.directory = String(path[..<slash])
            self.name = String(path[path.index(after: slash)...])
        } else {
            self.directory = ""
            self.name = path
        }
        self.status = status
        self.isStaged = isStaged
        self.additions = additions
        self.deletions = deletions
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FileChangeTests`
Expected: PASS (all three).

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Model/FileChange.swift Tests/GitWorkbenchTests/FileChangeTests.swift
git commit -m "Model: add FileChange with path-derived directory/name"
```

---

### Task 5: Diff value types

**Files:**
- Create: `Sources/GitWorkbench/Model/FileDiff.swift`

> Pure data shapes consumed by the diff renderer (Plan 4). No behavior to unit-test here; verified by build. Hunk/line `id`s default to `UUID()` per the handoff; Plan 4's parser tests compare by content, not id.

- [ ] **Step 1: Write the types**

`Sources/GitWorkbench/Model/FileDiff.swift`:

```swift
import Foundation

/// A file's diff: a list of hunks, each a list of lines (unified form).
/// The split renderer derives two columns from this (Plan 4).
public struct FileDiff: Sendable, Hashable {
    public var file: FileChange
    public var hunks: [DiffHunk]
    public var isBinary: Bool

    public init(file: FileChange, hunks: [DiffHunk], isBinary: Bool = false) {
        self.file = file
        self.hunks = hunks
        self.isBinary = isBinary
    }
}

public struct DiffHunk: Identifiable, Sendable, Hashable {
    public var id: UUID
    public var header: String           // "@@ -14,8 +14,9 @@"
    public var lines: [DiffLine]

    public init(id: UUID = UUID(), header: String, lines: [DiffLine]) {
        self.id = id
        self.header = header
        self.lines = lines
    }
}

public struct DiffLine: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case context, addition, deletion }

    public var id: UUID
    public var kind: Kind
    public var oldNumber: Int?          // line no. in old file (nil for additions)
    public var newNumber: Int?          // line no. in new file (nil for deletions)
    public var text: String             // raw content WITHOUT the +/-/space prefix

    public init(id: UUID = UUID(), kind: Kind, oldNumber: Int?, newNumber: Int?, text: String) {
        self.id = id
        self.kind = kind
        self.oldNumber = oldNumber
        self.newNumber = newNumber
        self.text = text
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/GitWorkbench/Model/FileDiff.swift
git commit -m "Model: add FileDiff/DiffHunk/DiffLine value types"
```

---

### Task 6: Remaining data models (Commit, Stash, Branch, RepositoryStatus)

**Files:**
- Create: `Sources/GitWorkbench/Model/Commit.swift`
- Create: `Sources/GitWorkbench/Model/Stash.swift`
- Create: `Sources/GitWorkbench/Model/Branch.swift`
- Create: `Sources/GitWorkbench/Model/RepositoryStatus.swift`

> Pure data shapes; verified by build.

- [ ] **Step 1: Write `Commit.swift`**

```swift
import Foundation

public struct Commit: Identifiable, Sendable, Hashable {
    public var id: String           // full SHA
    public var shortSHA: String     // "9f2c1a4"
    public var summary: String      // first line of the message
    public var body: String         // remainder (may be empty)
    public var authorName: String
    public var authorEmail: String
    public var authorInitials: String   // "GA" — for the monogram avatar
    public var date: String         // display string, e.g. "Today, 09:42"
    public var relativeDate: String // "3 hours ago"
    public var refs: [CommitRef]    // HEAD / branch / tag pills shown on the row
    public var parents: [String]    // parent short SHAs
    public var files: [FileChange]  // files changed in this commit

    public init(
        id: String, shortSHA: String, summary: String, body: String = "",
        authorName: String, authorEmail: String, authorInitials: String,
        date: String, relativeDate: String,
        refs: [CommitRef] = [], parents: [String] = [], files: [FileChange] = []
    ) {
        self.id = id; self.shortSHA = shortSHA; self.summary = summary; self.body = body
        self.authorName = authorName; self.authorEmail = authorEmail
        self.authorInitials = authorInitials; self.date = date; self.relativeDate = relativeDate
        self.refs = refs; self.parents = parents; self.files = files
    }
}

public enum CommitRef: Sendable, Hashable {
    case head                 // "HEAD" pill (accent)
    case branch(String)       // branch pill (blue) with branch glyph
    case tag(String)          // tag pill (green) with tag glyph
}
```

- [ ] **Step 2: Write `Stash.swift`**

```swift
import Foundation

public struct Stash: Identifiable, Sendable, Hashable {
    public var id: String          // stable key
    public var ref: String         // "stash@{0}"
    public var message: String     // "WIP: tune retry delays"
    public var branch: String      // branch it was created on
    public var date: String        // "Today, 12:05"
    public var relativeDate: String// "40 minutes ago"
    public var files: [FileChange]

    public init(
        id: String, ref: String, message: String, branch: String,
        date: String, relativeDate: String, files: [FileChange] = []
    ) {
        self.id = id; self.ref = ref; self.message = message; self.branch = branch
        self.date = date; self.relativeDate = relativeDate; self.files = files
    }
}
```

- [ ] **Step 3: Write `Branch.swift`**

```swift
import Foundation

public struct Branch: Identifiable, Sendable, Hashable {
    public var id: String          // branch name
    public var name: String        // "feat/auto-sync"
    public var isCurrent: Bool
    public var upstream: String?   // "origin/feat/auto-sync"

    public init(name: String, isCurrent: Bool = false, upstream: String? = nil) {
        self.id = name; self.name = name; self.isCurrent = isCurrent; self.upstream = upstream
    }
}
```

- [ ] **Step 4: Write `RepositoryStatus.swift`**

```swift
import Foundation

public struct RepositoryStatus: Sendable, Hashable {
    public var repositoryName: String   // "aurora-cli"
    public var currentBranch: String    // "feat/auto-sync"
    public var upstream: String?        // "origin/feat/auto-sync"
    public var ahead: Int               // commits to push
    public var behind: Int              // commits to pull
    public var files: [FileChange]      // all changed files (staged flag set per file)
    public var author: Author           // current user, for the composer avatar

    public init(
        repositoryName: String, currentBranch: String, upstream: String? = nil,
        ahead: Int = 0, behind: Int = 0, files: [FileChange] = [], author: Author
    ) {
        self.repositoryName = repositoryName; self.currentBranch = currentBranch
        self.upstream = upstream; self.ahead = ahead; self.behind = behind
        self.files = files; self.author = author
    }
}

public struct Author: Sendable, Hashable {
    public var name: String
    public var initials: String
    public init(name: String, initials: String) { self.name = name; self.initials = initials }
}
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/GitWorkbench/Model/Commit.swift Sources/GitWorkbench/Model/Stash.swift Sources/GitWorkbench/Model/Branch.swift Sources/GitWorkbench/Model/RepositoryStatus.swift
git commit -m "Model: add Commit/CommitRef, Stash, Branch, RepositoryStatus/Author"
```

---

### Task 7: Public configuration types + Toast

**Files:**
- Create: `Sources/GitWorkbench/Configuration.swift`
- Create: `Sources/GitWorkbench/Store/Toast.swift`

> Pure value types; verified by build.

- [ ] **Step 1: Write `Configuration.swift`**

```swift
import CoreGraphics

public enum WorkspaceView: String, CaseIterable, Sendable, Hashable {
    case changes, history, stashes
}

public enum DiffMode: String, Sendable, Hashable {
    case unified, split
}

public struct WorkbenchLayout: Sendable, Hashable {
    public var railWidth: CGFloat = 218
    public var changesListWidth: CGFloat = 320
    public var historyListWidth: CGFloat = 360
    public var minRailWidth: CGFloat = 180
    public var minDiffWidth: CGFloat = 420
    public var toolbarHeight: CGFloat = 52
    public init() {}
}

public struct WorkbenchConfiguration: Sendable {
    /// Draw the component's own toolbar bar (default). Set false if the host
    /// projects actions into a native NSToolbar / .toolbar instead.
    public var showsToolbar: Bool = true
    /// Default diff presentation when no per-repo preference is stored.
    public var defaultDiffMode: DiffMode = .split
    /// Which workspace view is shown first.
    public var initialView: WorkspaceView = .changes
    /// Optional per-repository persistence key; nil disables persistence.
    public var persistenceKey: String? = nil
    /// Pane sizing.
    public var layout: WorkbenchLayout = .init()

    public init() {}
}
```

> `WorkbenchTheme` is referenced by `WorkbenchConfiguration` in the handoff but is defined in Task 10; the configuration's `theme` property is added in Task 10 to avoid a forward reference.

- [ ] **Step 2: Write `Store/Toast.swift`**

```swift
import Foundation

public struct Toast: Identifiable, Sendable, Equatable {
    public enum Style: Sendable, Equatable { case success, info, error, progress }
    public var id: UUID
    public var message: String
    public var style: Style

    public init(id: UUID = UUID(), message: String, style: Style = .success) {
        self.id = id; self.message = message; self.style = style
    }

    public static func success(_ message: String) -> Toast { .init(message: message, style: .success) }
    public static func info(_ message: String) -> Toast { .init(message: message, style: .info) }
    public static func error(_ message: String) -> Toast { .init(message: message, style: .error) }
    public static func progress(_ message: String) -> Toast { .init(message: message, style: .progress) }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/GitWorkbench/Configuration.swift Sources/GitWorkbench/Store/Toast.swift
git commit -m "Add public configuration types and Toast"
```

---

### Task 8: `WorkbenchState` with derived properties

**Files:**
- Create: `Sources/GitWorkbench/Store/WorkbenchState.swift`
- Test: `Tests/GitWorkbenchTests/WorkbenchStateTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/GitWorkbenchTests/WorkbenchStateTests.swift`:

```swift
import XCTest
@testable import GitWorkbench

final class WorkbenchStateTests: XCTestCase {
    private func makeState(files: [FileChange], message: String = "") -> WorkbenchState {
        let repo = RepositoryStatus(
            repositoryName: "demo", currentBranch: "main", ahead: 0, behind: 0,
            files: files, author: Author(name: "Dev", initials: "DV")
        )
        var s = WorkbenchState(repo: repo)
        s.commitMessage = message
        return s
    }

    func test_stagedAndUnstagedPartitionByFlag() {
        let staged = FileChange(path: "a.txt", status: .modified, isStaged: true)
        let unstaged = FileChange(path: "b.txt", status: .modified, isStaged: false)
        let s = makeState(files: [staged, unstaged])
        XCTAssertEqual(s.staged.map(\.id), ["a.txt"])
        XCTAssertEqual(s.unstaged.map(\.id), ["b.txt"])
    }

    func test_canCommitRequiresStagedFileAndNonBlankMessage() {
        let staged = FileChange(path: "a.txt", status: .modified, isStaged: true)

        XCTAssertFalse(makeState(files: [staged], message: "").canCommit)        // no message
        XCTAssertFalse(makeState(files: [staged], message: "   \n").canCommit)   // blank message
        XCTAssertFalse(makeState(files: [], message: "msg").canCommit)           // nothing staged
        XCTAssertTrue(makeState(files: [staged], message: "fix bug").canCommit)  // both present
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkbenchStateTests`
Expected: FAIL — `WorkbenchState` undefined.

- [ ] **Step 3: Write the implementation**

`Sources/GitWorkbench/Store/WorkbenchState.swift`:

```swift
import Foundation

/// The value snapshot the whole view tree is a function of.
public struct WorkbenchState: Sendable {
    // active view + diff mode
    public var activeView: WorkspaceView = .changes
    public var diffMode: DiffMode = .split

    // repo status
    public var repo: RepositoryStatus
    public var branches: [Branch] = []

    // changes view
    public var selectedFileID: FileChange.ID?
    public var commitMessage: String = ""
    public var pendingDiscard: FileChange?     // non-nil → confirm popover up

    // history view
    public var commits: [Commit] = []
    public var selectedCommitID: Commit.ID?
    public var selectedCommitFileID: FileChange.ID?

    // stash view
    public var stashes: [Stash] = []
    public var selectedStashID: Stash.ID?
    public var selectedStashFileID: FileChange.ID?

    // diff cache for the currently shown file
    public var currentDiff: FileDiff?

    // transient
    public var isBusy: Bool = false
    public var toast: Toast?
    public var branchMenuOpen: Bool = false

    public init(repo: RepositoryStatus) { self.repo = repo }

    // derived
    public var staged: [FileChange] { repo.files.filter(\.isStaged) }
    public var unstaged: [FileChange] { repo.files.filter { !$0.isStaged } }
    public var canCommit: Bool {
        !staged.isEmpty &&
        !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WorkbenchStateTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitWorkbench/Store/WorkbenchState.swift Tests/GitWorkbenchTests/WorkbenchStateTests.swift
git commit -m "Store: add WorkbenchState with staged/unstaged/canCommit derivations"
```

---

### Task 9: `Tokens` metrics enum

**Files:**
- Create: `Sources/GitWorkbench/Theme/Tokens.swift`

> Static metric constants from `04-design-tokens.md §4.3`. Verified by build.

- [ ] **Step 1: Write the implementation**

`Sources/GitWorkbench/Theme/Tokens.swift`:

```swift
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
    public static let listRowInsetH: CGFloat = 12
    public static let toastBottomInset: CGFloat = 26
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/GitWorkbench/Theme/Tokens.swift
git commit -m "Theme: add Tokens metric constants"
```

---

### Task 10: `WorkbenchTheme` (colors, light/dark, accent toggle)

**Files:**
- Create: `Sources/GitWorkbench/Theme/WorkbenchTheme.swift`
- Modify: `Sources/GitWorkbench/Configuration.swift` (add the `theme` property)
- Test: `Tests/GitWorkbenchTests/WorkbenchThemeTests.swift`

> Colors from `04-design-tokens.md §4.1`. The light variant uses the literal purple-identity hexes (exact match to the prototype). The dark variant raises diff-tint alpha ~1.5× and lightens add/del ink per the §4.1 dark-mode note. `adoptsSystemAccent` swaps the accent for `NSColor.controlAccentColor`.

- [ ] **Step 1: Write the failing test**

`Tests/GitWorkbenchTests/WorkbenchThemeTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import GitWorkbench

final class WorkbenchThemeTests: XCTestCase {
    private func rgb(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        return (ns.redComponent, ns.greenComponent, ns.blueComponent)
    }

    func test_standardIsPurpleIdentityAndDoesNotAdoptSystemAccent() {
        let theme = WorkbenchTheme.standard
        XCTAssertFalse(theme.adoptsSystemAccent)
        let c = rgb(theme.accent)
        XCTAssertEqual(c.r, 0x7C / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.g, 0x5C / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.b, 0xE0 / 255.0, accuracy: 0.01)
    }

    func test_systemAccentVariantSetsFlag() {
        let theme = WorkbenchTheme.standard.adoptingSystemAccent()
        XCTAssertTrue(theme.adoptsSystemAccent)
    }

    func test_darkVariantExists() {
        // Dark surfaces differ from light surfaces.
        let light = rgb(WorkbenchTheme.standard.winBg)
        let dark = rgb(WorkbenchTheme.darkStandard.winBg)
        XCTAssertNotEqual(light.r, dark.r, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkbenchThemeTests`
Expected: FAIL — `WorkbenchTheme` undefined.

- [ ] **Step 3: Write the implementation**

`Sources/GitWorkbench/Theme/WorkbenchTheme.swift`:

```swift
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

    /// Returns a copy that uses the system accent (`NSColor.controlAccentColor`),
    /// deriving the soft/ring/deep variants from it (§4.1).
    public func adoptingSystemAccent() -> WorkbenchTheme {
        var copy = self
        let sys = Color(nsColor: .controlAccentColor)
        copy.adoptsSystemAccent = true
        copy.accent = sys
        copy.accentSoft = sys.opacity(0.13)
        copy.accentRing = sys.opacity(0.45)
        copy.accentDeep = sys                 // blended-toward-black handled at use sites if needed
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
```

- [ ] **Step 4: Add the `theme` property to `WorkbenchConfiguration`**

In `Sources/GitWorkbench/Configuration.swift`, inside `WorkbenchConfiguration`, add after the `layout` property:

```swift
    /// Visual theme (light identity by default).
    public var theme: WorkbenchTheme = .standard
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter WorkbenchThemeTests`
Expected: PASS (all three).

- [ ] **Step 6: Commit**

```bash
git add Sources/GitWorkbench/Theme/WorkbenchTheme.swift Sources/GitWorkbench/Configuration.swift Tests/GitWorkbenchTests/WorkbenchThemeTests.swift
git commit -m "Theme: add WorkbenchTheme light/dark color sets + system-accent toggle"
```

---

### Task 11: `IconLibrary` SF Symbols mapping

**Files:**
- Create: `Sources/GitWorkbench/Theme/IconLibrary.swift`

> SF Symbol names from `04-design-tokens.md §4.7`. Verified by build.

- [ ] **Step 1: Write the implementation**

`Sources/GitWorkbench/Theme/IconLibrary.swift`:

```swift
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
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/GitWorkbench/Theme/IconLibrary.swift
git commit -m "Theme: add IconLibrary SF Symbols mapping"
```

---

### Task 12: Mock fixtures + integrity tests

**Files:**
- Create: `Sources/GitWorkbench/Provider/Fixtures.swift`
- Test: `Tests/GitWorkbenchTests/FixturesTests.swift`

> Mirrors `reference/src/gitdata.js` metadata exactly (repo `aurora-cli`: 7 files, 6 commits, 2 stashes, 4 branches, ahead 2 / behind 1). Diff **hunks** (the per-file `FileDiff` content) are deferred to the diff-renderer plan where they're rendered and tested; these fixtures carry file/commit/stash **metadata** only.

- [ ] **Step 1: Write the failing test**

`Tests/GitWorkbenchTests/FixturesTests.swift`:

```swift
import XCTest
@testable import GitWorkbench

final class FixturesTests: XCTestCase {
    func test_repositoryHeadline() {
        let s = Fixtures.repositoryStatus
        XCTAssertEqual(s.repositoryName, "aurora-cli")
        XCTAssertEqual(s.currentBranch, "feat/auto-sync")
        XCTAssertEqual(s.upstream, "origin/feat/auto-sync")
        XCTAssertEqual(s.ahead, 2)
        XCTAssertEqual(s.behind, 1)
        XCTAssertEqual(s.author, Author(name: "Gustavo", initials: "GA"))
    }

    func test_fileCountsAndStagedSplit() {
        XCTAssertEqual(Fixtures.repositoryStatus.files.count, 7)
        let staged = Fixtures.repositoryStatus.files.filter(\.isStaged)
        let unstaged = Fixtures.repositoryStatus.files.filter { !$0.isStaged }
        XCTAssertEqual(staged.map(\.path), ["src/commands/sync.ts", "src/index.ts", "src/utils/logger.ts"])
        XCTAssertEqual(unstaged.count, 4)
    }

    func test_commitCountAndRefs() {
        XCTAssertEqual(Fixtures.commits.count, 6)
        XCTAssertEqual(Fixtures.commits.first?.shortSHA, "9f2c1a4")
        XCTAssertEqual(Fixtures.commits.first?.refs, [.head, .branch("feat/auto-sync")])
        XCTAssertEqual(Fixtures.commits.first(where: { $0.shortSHA == "a17f9c0" })?.refs, [.tag("v0.5.0-rc.1")])
    }

    func test_stashAndBranchCounts() {
        XCTAssertEqual(Fixtures.stashes.count, 2)
        XCTAssertEqual(Fixtures.stashes.first?.ref, "stash@{0}")
        XCTAssertEqual(Fixtures.branches.map(\.name), ["main", "develop", "feat/auto-sync", "fix/log-levels"])
        XCTAssertEqual(Fixtures.branches.first(where: \.isCurrent)?.name, "feat/auto-sync")
    }

    func test_initialStateBuildsFromFixtures() {
        let s = Fixtures.initialState
        XCTAssertEqual(s.repo.files.count, 7)
        XCTAssertEqual(s.commits.count, 6)
        XCTAssertEqual(s.stashes.count, 2)
        XCTAssertEqual(s.branches.count, 4)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FixturesTests`
Expected: FAIL — `Fixtures` undefined.

- [ ] **Step 3: Write the implementation**

`Sources/GitWorkbench/Provider/Fixtures.swift`:

```swift
import Foundation

/// In-memory fixture data mirroring reference/src/gitdata.js (repo "aurora-cli").
/// Metadata only — diff hunks are added in the diff-renderer plan.
public enum Fixtures {
    public static let author = Author(name: "Gustavo", initials: "GA")

    // MARK: Working-tree files (7)
    public static let files: [FileChange] = [
        FileChange(path: "src/commands/sync.ts", status: .modified, isStaged: true, additions: 24, deletions: 6),
        FileChange(path: "src/index.ts", status: .modified, isStaged: true, additions: 8, deletions: 2),
        FileChange(path: "src/utils/logger.ts", status: .added, isStaged: true, additions: 31, deletions: 0),
        FileChange(path: "package.json", status: .modified, isStaged: false, additions: 3, deletions: 1),
        FileChange(path: "README.md", status: .modified, isStaged: false, additions: 5, deletions: 0),
        FileChange(path: "src/legacy/poller.ts", status: .deleted, isStaged: false, additions: 0, deletions: 18),
        FileChange(path: ".env.example", status: .untracked, isStaged: false, additions: 4, deletions: 0),
    ]

    public static let repositoryStatus = RepositoryStatus(
        repositoryName: "aurora-cli",
        currentBranch: "feat/auto-sync",
        upstream: "origin/feat/auto-sync",
        ahead: 2, behind: 1,
        files: files, author: author
    )

    // MARK: Commit history (6, newest first)
    public static let commits: [Commit] = [
        Commit(
            id: "9f2c1a4e7b3", shortSHA: "9f2c1a4",
            summary: "Add structured Logger with level colors",
            body: "Replaces scattered console.log calls with a scoped Logger that writes\nleveled, colorized output to stderr. Wires it through the sync command.",
            authorName: "Gustavo", authorEmail: "gustavo@aurora.dev", authorInitials: "GA",
            date: "Today, 09:42", relativeDate: "3 hours ago",
            refs: [.head, .branch("feat/auto-sync")], parents: ["3b8e7d2"],
            files: [
                FileChange(path: "src/utils/logger.ts", status: .added, additions: 31, deletions: 0),
                FileChange(path: "src/commands/sync.ts", status: .modified, additions: 4, deletions: 1),
            ]
        ),
        Commit(
            id: "3b8e7d2f1a9", shortSHA: "3b8e7d2",
            summary: "Switch watcher to fs.watch, drop poller",
            body: "The legacy interval poller is replaced by an fs.watch-based watcher\nfor lower latency and CPU. Removes src/legacy/poller.ts.",
            authorName: "Gustavo", authorEmail: "gustavo@aurora.dev", authorInitials: "GA",
            date: "Yesterday, 18:20", relativeDate: "1 day ago",
            refs: [], parents: ["a17f9c0"],
            files: [
                FileChange(path: "src/commands/watch.ts", status: .added, additions: 22, deletions: 0),
                FileChange(path: "src/legacy/poller.ts", status: .deleted, additions: 0, deletions: 9),
            ]
        ),
        Commit(
            id: "a17f9c0b5e2", shortSHA: "a17f9c0",
            summary: "Bump CLI to 0.5.0-rc.1",
            body: "Pre-release cut for the auto-sync feature branch.",
            authorName: "Mira Patel", authorEmail: "mira@aurora.dev", authorInitials: "MP",
            date: "Mon, 14:05", relativeDate: "3 days ago",
            refs: [.tag("v0.5.0-rc.1")], parents: ["e4d5b61"],
            files: [FileChange(path: "package.json", status: .modified, additions: 1, deletions: 1)]
        ),
        Commit(
            id: "e4d5b61c8d4", shortSHA: "e4d5b61",
            summary: "Format `status` command output as a table",
            body: "Aligns the working-tree status output into columns with status glyphs.",
            authorName: "Mira Patel", authorEmail: "mira@aurora.dev", authorInitials: "MP",
            date: "Mon, 11:32", relativeDate: "3 days ago",
            refs: [], parents: ["77ac3f9"],
            files: [FileChange(path: "src/commands/status.ts", status: .modified, additions: 14, deletions: 6)]
        ),
        Commit(
            id: "77ac3f9d2b6", shortSHA: "77ac3f9",
            summary: "Scaffold sync retry loop",
            body: "First pass at the push retry loop (fixed delay; backoff comes later).",
            authorName: "Gustavo", authorEmail: "gustavo@aurora.dev", authorInitials: "GA",
            date: "Sun, 22:14", relativeDate: "4 days ago",
            refs: [], parents: ["1c0aa28"],
            files: [FileChange(path: "src/commands/sync.ts", status: .added, additions: 18, deletions: 0)]
        ),
        Commit(
            id: "1c0aa28f0c1", shortSHA: "1c0aa28",
            summary: "chore: project scaffolding",
            body: "Initial TypeScript + tsup setup.",
            authorName: "Mira Patel", authorEmail: "mira@aurora.dev", authorInitials: "MP",
            date: "Sat, 10:00", relativeDate: "5 days ago",
            refs: [.branch("main")], parents: [],
            files: [FileChange(path: "package.json", status: .added, additions: 12, deletions: 0)]
        ),
    ]

    // MARK: Stashes (2)
    public static let stashes: [Stash] = [
        Stash(
            id: "stash0", ref: "stash@{0}", message: "WIP: tune retry delays",
            branch: "feat/auto-sync", date: "Today, 12:05", relativeDate: "40 minutes ago",
            files: [FileChange(path: "src/commands/sync.ts", status: .modified, additions: 3, deletions: 2)]
        ),
        Stash(
            id: "stash1", ref: "stash@{1}", message: "experiment: parallel push to mirrors",
            branch: "feat/auto-sync", date: "Sun, 19:48", relativeDate: "2 days ago",
            files: [
                FileChange(path: "src/commands/sync.ts", status: .modified, additions: 6, deletions: 1),
                FileChange(path: "src/config.ts", status: .modified, additions: 2, deletions: 0),
            ]
        ),
    ]

    // MARK: Branches (4)
    public static let branches: [Branch] = [
        Branch(name: "main", isCurrent: false, upstream: "origin/main"),
        Branch(name: "develop", isCurrent: false, upstream: "origin/develop"),
        Branch(name: "feat/auto-sync", isCurrent: true, upstream: "origin/feat/auto-sync"),
        Branch(name: "fix/log-levels", isCurrent: false, upstream: nil),
    ]

    /// A fully-populated initial state for previews and the (later) store/demo.
    public static var initialState: WorkbenchState {
        var s = WorkbenchState(repo: repositoryStatus)
        s.branches = branches
        s.commits = commits
        s.stashes = stashes
        return s
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FixturesTests`
Expected: PASS (all five).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: every test passes (ColorHex, FileStatus, FileChange, WorkbenchState, WorkbenchTheme, Fixtures, Smoke).

- [ ] **Step 6: Commit**

```bash
git add Sources/GitWorkbench/Provider/Fixtures.swift Tests/GitWorkbenchTests/FixturesTests.swift
git commit -m "Provider: add mock Fixtures mirroring gitdata.js metadata"
```

---

### Task 13: Empty workbench shell + preview

**Files:**
- Create: `Sources/GitWorkbench/GitWorkbenchView.swift`

> A skeleton `GitWorkbenchView` proving the package renders the 52pt toolbar bar + 218pt rail + empty body, themed and previewable. It takes a `WorkbenchState` directly via a temporary initializer; the store-backed public `init(store:)` arrives in Plan 2, and the real toolbar/rail components arrive in Plan 5. No store, no interactions yet. SwiftUI views aren't unit-tested here — verification is build + visual preview.

- [ ] **Step 1: Write the shell**

`Sources/GitWorkbench/GitWorkbenchView.swift`:

```swift
import SwiftUI

/// The reusable git-workbench component. Plan 1 renders a themed skeleton from a
/// `WorkbenchState` value; later plans add the store, real toolbar/rail, and views.
public struct GitWorkbenchView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let state: WorkbenchState
    private let configuration: WorkbenchConfiguration

    // NOTE (Plan 2): replaced/supplemented by `public init(store: GitWorkbenchStore, ...)`.
    init(state: WorkbenchState, configuration: WorkbenchConfiguration = .init()) {
        self.state = state
        self.configuration = configuration
    }

    private var theme: WorkbenchTheme {
        WorkbenchTheme.resolved(for: colorScheme,
                                adoptsSystemAccent: configuration.theme.adoptsSystemAccent)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if configuration.showsToolbar { toolbarSkeleton }
            HStack(spacing: 0) {
                railSkeleton
                bodySkeleton
            }
        }
        .background(theme.winBg)
        .foregroundStyle(theme.ink)
    }

    private var toolbarSkeleton: some View {
        HStack(spacing: 0) {
            Text(state.repo.repositoryName)
                .font(.system(size: 13, weight: .bold))
                .padding(.leading, 20)
                .frame(width: configuration.layout.railWidth, alignment: .leading)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) { Rectangle().fill(theme.sep).frame(width: 1) }
            Spacer(minLength: 0)
        }
        .frame(height: configuration.layout.toolbarHeight)
        .background(theme.titlebar)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }

    private var railSkeleton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WORKSPACE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(theme.ink3)
                .padding(.init(top: 14, leading: 16, bottom: 5, trailing: 16))
            Spacer()
        }
        .frame(width: configuration.layout.railWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(theme.sidebarDeep)
    }

    private var bodySkeleton: some View {
        VStack(spacing: 6) {
            Image(systemName: IconLibrary.file)
                .font(.system(size: 22))
                .foregroundStyle(theme.ink3)
            Text("Select a file to view changes")
                .font(.system(size: 12))
                .foregroundStyle(theme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.winBg)
    }
}

#Preview("Workbench shell — light") {
    GitWorkbenchView(state: Fixtures.initialState)
        .frame(width: 980, height: 600)
}

#Preview("Workbench shell — dark") {
    GitWorkbenchView(state: Fixtures.initialState)
        .frame(width: 980, height: 600)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Verify the preview renders**

Open `Sources/GitWorkbench/GitWorkbenchView.swift` in Xcode (`xed .` from the repo root, or open `Package.swift` in Xcode) and resume the canvas. Confirm both previews show: a 52pt top bar reading "aurora-cli", a 218pt left rail with a "WORKSPACE" header on the deep sidebar tint, and a centered empty-state body — correct in both light and dark.

- [ ] **Step 4: Commit**

```bash
git add Sources/GitWorkbench/GitWorkbenchView.swift
git commit -m "P0: add empty GitWorkbenchView shell with light/dark previews"
```

---

## Self-Review

**1. Spec coverage (vs. design spec §5 + handoff P0/02):**
- Package.swift (macOS 15, Swift 6, zero deps) → Task 1 ✓
- Model layer: FileStatus, FileChange (derivation), FileDiff/DiffHunk/DiffLine, Commit/CommitRef, Stash, Branch, RepositoryStatus/Author, WorkbenchState, Toast → Tasks 3–8, 7 ✓
- Public config (WorkspaceView, DiffMode, WorkbenchConfiguration, WorkbenchLayout) → Task 7 ✓
- Theme (colors light/dark, accent toggle), Tokens, IconLibrary → Tasks 9–11 ✓
- Mock fixtures mirroring gitdata.js metadata → Task 12 ✓
- Empty GitWorkbenchView shell + previews → Task 13 ✓
- **Deferred by design (later plans, noted in-plan):** diff hunk fixtures + renderer (Plan 4); `GitWorkbenchStore` + `MockGitProvider` + `init(store:)` (Plan 2); real toolbar/rail (Plan 5); Avatar OKLCH color (Plan 3); `GitWorkbenchDemo` executable target (Plan 9).

**2. Placeholder scan:** No "TBD/TODO/handle later" in code steps; every code step shows complete code; every command lists expected output. The two `NOTE (Plan N)` comments mark deliberate forward evolution, not missing content.

**3. Type consistency:** `FileChange(path:status:isStaged:additions:deletions:)` and the `id:` overload are used identically in Tasks 4, 8, 12. `WorkbenchState(repo:)` init + `.staged`/`.unstaged`/`.canCommit` match between Tasks 8 and 12. `WorkbenchTheme.standard`/`.darkStandard`/`.resolved(for:adoptsSystemAccent:)`/`.adoptingSystemAccent()` defined in Task 10 and used in Tasks 12–13. `CommitRef` cases (`.head`, `.branch`, `.tag`) consistent across Tasks 6, 11, 12. `Fixtures.initialState`/`.repositoryStatus`/`.commits`/`.stashes`/`.branches` defined in Task 12 and consumed in Task 13. `WorkbenchConfiguration.theme` added in Task 10 before use in Task 13. No mismatches found.
