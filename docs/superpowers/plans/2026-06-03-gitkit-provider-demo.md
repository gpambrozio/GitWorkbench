# GitWorkbenchGitKit — CLIGitProvider + Live Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Wire the GitKit parsers into `CLIGitProvider` (a `GitWorkbenchProvider` backed by the real `git` CLI) and ship a `GitWorkbenchLiveDemo` app that runs the component against a real repository.

**Architecture:** Plan 10 (the core component + GitKit git layer are on `main`). `CLIGitProvider` is a `Sendable struct` holding a `GitRunner` (no mutable state — each git op spawns a process). Reads map protocol methods to git commands feeding the parsers (merging numstat counts, attaching per-commit/stash files); actions run git mutating commands. The live demo opens a repo path and hosts `GitWorkbenchView(GitWorkbenchStore(provider:))`. Integration tests run the provider against temporary real repos created in `setUp`.

**Tech Stack:** Swift 6, SwiftPM, macOS 15+, XCTest, Foundation, AppKit (demo). No third-party deps.

**Conventions:** Provider reads/actions throw `GitError` (the store surfaces them as toasts). Integration tests create temp repos via `git`; skip gracefully if `git` is unavailable. Run from repo root; execution on `feat/gitkit-provider`. Verify via the live demo `--shot` against THIS repo.

---

### Task 1: CLIGitProvider — reads

**Files:**
- Create: `Sources/GitWorkbenchGitKit/CLIGitProvider.swift`
- Test: `Tests/GitWorkbenchGitKitTests/CLIGitProviderTests.swift`

- [ ] **Step 1: Write `CLIGitProvider.swift` (reads + helpers)**

```swift
import Foundation
import GitWorkbench

/// A `GitWorkbenchProvider` backed by the system `git` CLI. Read side here; actions in an extension.
public struct CLIGitProvider: GitWorkbenchProvider {
    let runner: GitRunner
    static let logFormat = "%H%x1f%h%x1f%an%x1f%ae%x1f%aI%x1f%cI%x1f%P%x1f%D%x1f%s%x1f%b%x1e"

    public init(repositoryURL: URL, gitPath: String = "/usr/bin/git") {
        self.runner = GitRunner(repositoryURL: repositoryURL, gitPath: gitPath)
    }

    /// Throws `GitError.notARepository` unless the directory is a git work tree.
    public func validate() async throws {
        let result = try await runner.run(["rev-parse", "--is-inside-work-tree"])
        guard result.exitCode == 0,
              result.text.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw GitError.notARepository(runner.repositoryURL.path)
        }
    }

    // MARK: GitWorkbenchDataSource

    public func loadStatus() async throws -> RepositoryStatus {
        let porcelain = try await runner.output(["status", "--porcelain=v2", "--branch", "-z"]).text
        let parsed = StatusParser.parse(porcelain: porcelain)
        async let unstagedText = runner.output(["diff", "--numstat", "-z"]).text
        async let stagedText = runner.output(["diff", "--cached", "--numstat", "-z"]).text
        let unstaged = NumstatParser.parse(try await unstagedText)
        let staged = NumstatParser.parse(try await stagedText)
        let files = parsed.files.map { file -> FileChange in
            let counts = file.isStaged ? staged[file.path] : unstaged[file.path]
            return FileChange(id: file.id, path: file.path, status: file.status, isStaged: file.isStaged,
                              additions: counts?.additions ?? 0, deletions: counts?.deletions ?? 0)
        }
        let toplevel = ((try? await runner.output(["rev-parse", "--show-toplevel"]).text) ?? runner.repositoryURL.path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return RepositoryStatus(
            repositoryName: URL(fileURLWithPath: toplevel).lastPathComponent,
            currentBranch: parsed.branch, upstream: parsed.upstream,
            ahead: parsed.ahead, behind: parsed.behind, files: files, author: try await author())
    }

    public func loadBranches() async throws -> [Branch] {
        let out = try await runner.output(["for-each-ref",
            "--format=%(refname:short)\u{1f}%(upstream:short)\u{1f}%(HEAD)", "refs/heads"]).text
        return RefParser.parse(out)
    }

    public func loadStashes() async throws -> [Stash] {
        let out = try await runner.output(["stash", "list", "--format=%gd\u{1f}%s\u{1f}%cr"]).text
        let branch = (try? await currentBranch()) ?? ""
        var stashes = StashParser.parse(out, branch: branch)
        for index in stashes.indices {
            stashes[index].files = (try? await stashFiles(stashes[index].ref)) ?? []
        }
        return stashes
    }

    public func loadHistory(before: Commit.ID?, limit: Int) async throws -> [Commit] {
        var args = ["log", "--format=\(Self.logFormat)", "--max-count=\(limit)"]
        if let before { args.append("\(before)^") }
        let out = try await runner.output(args).text
        var commits = LogParser.parse(out)
        for index in commits.indices {
            commits[index].files = (try? await commitFiles(commits[index].id)) ?? []
            if commits[index].relativeDate.isEmpty { commits[index].relativeDate = commits[index].date }
        }
        return commits
    }

    public func loadDiff(_ request: DiffRequest) async throws -> FileDiff {
        let text: String
        switch request.context {
        case .workingTree(let staged):
            let args = staged ? ["diff", "--cached", "--", request.file.path]
                              : ["diff", "--", request.file.path]
            text = try await runner.output(args).text
        case .commit(let id):
            text = try await runner.output(["show", id, "--format=", "--", request.file.path]).text
        case .stash(let id):
            text = try await runner.output(["stash", "show", "-p", id, "--", request.file.path]).text
        }
        return DiffParser.parse(unifiedDiff: text, file: request.file)
    }

    // MARK: Helpers

    func author() async throws -> Author {
        let name = ((try? await runner.output(["config", "user.name"]).text) ?? "You")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = name.isEmpty ? "You" : name
        return Author(name: safe, initials: LogParser.initials(for: safe))
    }

    func currentBranch() async throws -> String {
        try await runner.output(["rev-parse", "--abbrev-ref", "HEAD"]).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func commitFiles(_ sha: String) async throws -> [FileChange] {
        async let nameStatus = runner.output(["show", sha, "--name-status", "--format=", "-z"]).text
        async let numstat = runner.output(["show", sha, "--numstat", "--format=", "-z"]).text
        let counts = NumstatParser.parse(try await numstat)
        return Self.parseNameStatus(try await nameStatus).map { status, path in
            FileChange(path: path, status: status,
                       additions: counts[path]?.additions ?? 0, deletions: counts[path]?.deletions ?? 0)
        }
    }

    func stashFiles(_ ref: String) async throws -> [FileChange] {
        async let nameStatus = runner.output(["stash", "show", "--name-status", "-z", ref]).text
        async let numstat = runner.output(["stash", "show", "--numstat", "-z", ref]).text
        let counts = NumstatParser.parse(try await numstat)
        return Self.parseNameStatus(try await nameStatus).map { status, path in
            FileChange(path: path, status: status,
                       additions: counts[path]?.additions ?? 0, deletions: counts[path]?.deletions ?? 0)
        }
    }

    /// Parses `--name-status -z`: each record is a STATUS code then its path(s) (rename = old, new).
    static func parseNameStatus(_ output: String) -> [(FileStatus, String)] {
        let tokens = output.split(separator: "\u{0}", omittingEmptySubsequences: true).map(String.init)
        var result: [(FileStatus, String)] = []
        var i = 0
        while i < tokens.count {
            let code = tokens[i]; i += 1
            guard i < tokens.count else { break }
            let first = code.first ?? "M"
            if first == "R" || first == "C" {            // rename/copy: <old> <new> — keep the new path
                i += 1                                     // skip old
                if i < tokens.count { result.append((.renamed, tokens[i])); i += 1 }
            } else {
                result.append((mapStatus(first), tokens[i])); i += 1
            }
        }
        return result
    }

    private static func mapStatus(_ c: Character) -> FileStatus {
        switch c { case "A": .added; case "D": .deleted; case "R", "C": .renamed; case "U": .conflicted; default: .modified }
    }
}
```

- [ ] **Step 2: Write the integration test**

`Tests/GitWorkbenchGitKitTests/CLIGitProviderTests.swift`:

```swift
import XCTest
@testable import GitWorkbenchGitKit
import GitWorkbench

final class CLIGitProviderTests: XCTestCase {
    private var repo: URL!
    private var provider: CLIGitProvider!

    override func setUp() async throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gwbtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        provider = CLIGitProvider(repositoryURL: repo)
        // Build a small real repo.
        try await git(["init", "-b", "main"])
        try await git(["config", "user.email", "t@example.com"])
        try await git(["config", "user.name", "Test User"])
        try await git(["config", "commit.gpgsign", "false"])
        try write("a.txt", "one\ntwo\nthree\n")
        try await git(["add", "a.txt"])
        try await git(["commit", "-m", "first commit"])
        // a committed second file + an unstaged edit + a staged new file + an untracked file
        try write("a.txt", "one\nTWO\nthree\nfour\n")    // unstaged modify
        try write("b.txt", "new file\n"); try await git(["add", "b.txt"])  // staged add
        try write("c.txt", "untracked\n")               // untracked
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: repo)
    }

    private func git(_ args: [String]) async throws {
        _ = try await GitRunner(repositoryURL: repo).output(args)
    }
    private func write(_ name: String, _ contents: String) throws {
        try contents.write(to: repo.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func test_validatePasses() async throws { try await provider.validate() }

    func test_loadStatusReadsRealWorkingTree() async throws {
        let status = try await provider.loadStatus()
        XCTAssertEqual(status.currentBranch, "main")
        XCTAssertEqual(status.repositoryName, repo.lastPathComponent)
        // a.txt unstaged-modified, b.txt staged-added, c.txt untracked
        XCTAssertTrue(status.files.contains { $0.path == "a.txt" && !$0.isStaged && $0.status == .modified })
        XCTAssertTrue(status.files.contains { $0.path == "b.txt" && $0.isStaged && $0.status == .added })
        XCTAssertTrue(status.files.contains { $0.path == "c.txt" && $0.status == .untracked })
        // numstat merged: a.txt has +1 (added "four") and the modified line nets +1/-1
        let a = status.files.first { $0.path == "a.txt" }!
        XCTAssertGreaterThan(a.additions, 0)
    }

    func test_loadHistoryAndCommitFiles() async throws {
        let commits = try await provider.loadHistory(before: nil, limit: 10)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].summary, "first commit")
        XCTAssertEqual(commits[0].authorName, "Test User")
        XCTAssertEqual(commits[0].authorInitials, "TU")
        XCTAssertEqual(commits[0].files.map(\.path), ["a.txt"])
        XCTAssertEqual(commits[0].files.first?.status, .added)
    }

    func test_loadBranches() async throws {
        let branches = try await provider.loadBranches()
        XCTAssertEqual(branches.map(\.name), ["main"])
        XCTAssertTrue(branches[0].isCurrent)
    }

    func test_loadDiffForWorkingTreeFile() async throws {
        let file = FileChange(path: "a.txt", status: .modified, isStaged: false)
        let diff = try await provider.loadDiff(DiffRequest(file: file, context: .workingTree(staged: false), mode: .unified))
        XCTAssertFalse(diff.hunks.isEmpty)
        XCTAssertTrue(diff.hunks.flatMap { $0.lines }.contains { $0.kind == .addition })
    }

    func test_loadStashes() async throws {
        try await git(["stash", "push", "-u", "-m", "wip stash"])
        let stashes = try await provider.loadStashes()
        XCTAssertEqual(stashes.count, 1)
        XCTAssertTrue(stashes[0].message.contains("wip stash"))
        XCTAssertFalse(stashes[0].files.isEmpty)
    }
}
```

- [ ] **Step 3: Build, run, commit**

Run: `swift build && swift test --filter CLIGitProviderTests`
Expected: build succeeds; the integration tests pass (they shell out to real `git`). If a test fails, read its assertion against the actual git output — do NOT loosen assertions without understanding the mismatch.

```bash
git add Sources/GitWorkbenchGitKit/CLIGitProvider.swift Tests/GitWorkbenchGitKitTests/CLIGitProviderTests.swift
git commit -m "GitKit: add CLIGitProvider data-source reads + integration tests"
```

---

### Task 2: CLIGitProvider — actions

**Files:**
- Create: `Sources/GitWorkbenchGitKit/CLIGitProvider+Actions.swift`
- Test: `Tests/GitWorkbenchGitKitTests/CLIGitProviderActionTests.swift`

- [ ] **Step 1: Write `CLIGitProvider+Actions.swift`**

```swift
import Foundation
import GitWorkbench

extension CLIGitProvider {
    public func stage(_ files: [FileChange]) async throws {
        guard !files.isEmpty else { return }
        _ = try await runner.output(["add", "--"] + uniquePaths(files))
    }

    public func unstage(_ files: [FileChange]) async throws {
        guard !files.isEmpty else { return }
        _ = try await runner.output(["restore", "--staged", "--"] + uniquePaths(files))
    }

    public func discard(_ file: FileChange) async throws {
        if file.status == .untracked {
            _ = try await runner.output(["clean", "-f", "--", file.path])
        } else {
            _ = try await runner.output(["restore", "--", file.path])
        }
    }

    public func commit(message: String, staged: [FileChange]) async throws -> Commit {
        _ = try await runner.output(["commit", "-m", message])
        let out = try await runner.output(["log", "-1", "--format=\(Self.logFormat)"]).text
        guard var commit = LogParser.parse(out).first else {
            throw GitError.commandFailed(arguments: ["log", "-1"], code: 0, stderr: "could not read new commit")
        }
        commit.files = (try? await commitFiles(commit.id)) ?? staged
        if commit.relativeDate.isEmpty { commit.relativeDate = commit.date }
        return commit
    }

    public func pull() async throws -> SyncResult { try await sync(["pull"]) }
    public func push() async throws -> SyncResult { try await sync(["push"]) }
    public func fetch() async throws -> SyncResult { try await sync(["fetch"]) }

    public func switchBranch(to branch: Branch) async throws {
        _ = try await runner.output(["switch", branch.name])
    }

    public func applyStash(_ stash: Stash) async throws { _ = try await runner.output(["stash", "apply", stash.ref]) }
    public func popStash(_ stash: Stash) async throws { _ = try await runner.output(["stash", "pop", stash.ref]) }
    public func dropStash(_ stash: Stash) async throws { _ = try await runner.output(["stash", "drop", stash.ref]) }

    private func uniquePaths(_ files: [FileChange]) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for f in files where seen.insert(f.path).inserted { result.append(f.path) }
        return result
    }

    private func sync(_ args: [String]) async throws -> SyncResult {
        let result = try await runner.run(args)
        guard result.exitCode == 0 else {
            throw GitError.commandFailed(arguments: args, code: result.exitCode, stderr: result.stderr)
        }
        let status = try await loadStatus()
        let raw = result.stderr.isEmpty ? result.text : result.stderr
        let line = raw.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces)
        return SyncResult(ahead: status.ahead, behind: status.behind,
                          message: (line?.isEmpty == false ? line! : "Up to date with origin"))
    }
}
```

- [ ] **Step 2: Write the action integration test**

`Tests/GitWorkbenchGitKitTests/CLIGitProviderActionTests.swift`:

```swift
import XCTest
@testable import GitWorkbenchGitKit
import GitWorkbench

final class CLIGitProviderActionTests: XCTestCase {
    private var repo: URL!
    private var provider: CLIGitProvider!

    override func setUp() async throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gwbact-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        provider = CLIGitProvider(repositoryURL: repo)
        let r = GitRunner(repositoryURL: repo)
        _ = try await r.output(["init", "-b", "main"])
        _ = try await r.output(["config", "user.email", "t@example.com"])
        _ = try await r.output(["config", "user.name", "Test User"])
        _ = try await r.output(["config", "commit.gpgsign", "false"])
        try "v1\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await r.output(["add", "a.txt"]); _ = try await r.output(["commit", "-m", "init"])
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: repo) }

    func test_stageThenUnstage() async throws {
        try "v2\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let file = FileChange(path: "a.txt", status: .modified)
        try await provider.stage([file])
        XCTAssertTrue(try await provider.loadStatus().files.contains { $0.path == "a.txt" && $0.isStaged })
        try await provider.unstage([file])
        XCTAssertTrue(try await provider.loadStatus().files.contains { $0.path == "a.txt" && !$0.isStaged })
    }

    func test_commitGrowsHistory() async throws {
        try "fresh\n".write(to: repo.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try await provider.stage([FileChange(path: "b.txt", status: .added)])
        let new = try await provider.commit(message: "add b", staged: [FileChange(path: "b.txt", status: .added)])
        XCTAssertEqual(new.summary, "add b")
        let history = try await provider.loadHistory(before: nil, limit: 10)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.summary, "add b")
    }

    func test_discardRevertsModification() async throws {
        try "changed\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try await provider.discard(FileChange(path: "a.txt", status: .modified))
        let contents = try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(contents, "v1\n")   // reverted to committed
    }

    func test_switchBranch() async throws {
        _ = try await GitRunner(repositoryURL: repo).output(["branch", "dev"])
        try await provider.switchBranch(to: Branch(name: "dev"))
        XCTAssertEqual(try await provider.loadStatus().currentBranch, "dev")
    }

    func test_stashApplyAndDrop() async throws {
        try "wip\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await GitRunner(repositoryURL: repo).output(["stash", "push", "-m", "wip"])
        let stash = try await provider.loadStashes()[0]
        try await provider.applyStash(stash)        // keeps it
        XCTAssertEqual(try await provider.loadStashes().count, 1)
        try await provider.dropStash(stash)
        XCTAssertEqual(try await provider.loadStashes().count, 0)
    }
}
```

- [ ] **Step 3: Build, run the full suite, commit**

Run: `swift build && swift test`
Expected: the whole suite passes (core 67 + GitKit parser tests + the new CLIGitProvider integration tests).

```bash
git add Sources/GitWorkbenchGitKit/CLIGitProvider+Actions.swift Tests/GitWorkbenchGitKitTests/CLIGitProviderActionTests.swift
git commit -m "GitKit: add CLIGitProvider action handler + integration tests"
```

---

### Task 3: GitWorkbenchLiveDemo

**Files:**
- Modify: `Package.swift` (add the `GitWorkbenchLiveDemo` executable target + product)
- Create: `Sources/GitWorkbenchLiveDemo/LiveDemoApp.swift`

> A windowed host that runs the component against a real repo (the path argument, or the current directory). Includes the same `--shot` snapshot mode as the mock demo, so we can capture it driving real git data.

- [ ] **Step 1: Add the target to `Package.swift`**

Add to `products:`:

```swift
        .executable(name: "GitWorkbenchLiveDemo", targets: ["GitWorkbenchLiveDemo"]),
```

Add to `targets:`:

```swift
        .executableTarget(
            name: "GitWorkbenchLiveDemo",
            dependencies: ["GitWorkbench", "GitWorkbenchGitKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
```

- [ ] **Step 2: Write `LiveDemoApp.swift`**

```swift
import SwiftUI
import AppKit
import GitWorkbench
import GitWorkbenchGitKit

@MainActor
enum LiveState {
    static let store: GitWorkbenchStore = {
        let path = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") && !$0.hasPrefix("/tmp/") }
            ?? FileManager.default.currentDirectoryPath
        return GitWorkbenchStore(provider: CLIGitProvider(repositoryURL: URL(fileURLWithPath: path)))
    }()
}

@MainActor
final class LiveDemoDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--shot"), i + 1 < args.count {
            runSnapshot(path: args[i + 1], view: value(args, "--view"), dark: args.contains("--dark"))
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func value(_ args: [String], _ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private func runSnapshot(path: String, view: String?, dark: Bool) {
        NSApp.setActivationPolicy(.accessory)
        let store = LiveState.store
        Task { @MainActor in
            NSApp.windows.first?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            await store.reload()
            switch view {
            case "history":
                store.select(.history)
                if let id = store.state.commits.first?.id { await store.selectCommit(id) }
            case "stashes":
                store.select(.stashes)
                if let id = store.state.stashes.first?.id { await store.selectStash(id) }
            default:
                store.select(.changes)
                if let f = store.state.repo.files.first { store.select(file: f.id) }
            }
            try? await Task.sleep(for: .milliseconds(1400))
            if let window = NSApp.windows.first(where: { $0.contentView != nil }),
               let view = window.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                    FileHandle.standardError.write(Data("SHOT \(path)\n".utf8))
                }
            }
            NSApp.terminate(nil)
        }
    }
}

@main
struct GitWorkbenchLiveDemoApp: App {
    @NSApplicationDelegateAdaptor(LiveDemoDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("GitWorkbench (Live)") {
            GitWorkbenchView(store: LiveState.store).frame(minWidth: 1080, minHeight: 660)
        }
        .defaultSize(width: 1200, height: 740)
    }
}
```

- [ ] **Step 3: Build & verify against a real repo**

Run:
```bash
swift build
.build/debug/GitWorkbenchLiveDemo --shot /tmp/live_history.png --view history . >/tmp/lv.log 2>&1 & sleep 9; pkill -f GitWorkbenchLiveDemo
```
Confirm `/tmp/live_history.png` is written and the log shows `SHOT` — this is the component rendering **real commit history from this repository** via `CLIGitProvider`.

- [ ] **Step 4: Run the full suite + commit**

Run: `swift test`
Expected: all tests pass (core + GitKit parsers + CLIGitProvider integration).

```bash
git add Package.swift Sources/GitWorkbenchLiveDemo
git commit -m "GitKit: add GitWorkbenchLiveDemo (component on a real repo)"
```

---

## Self-Review

**1. Spec coverage (vs. design spec §6.2 command mapping + §6.5 live demo):**
- `CLIGitProvider` reads: `loadStatus` (porcelain v2 + numstat merge + repo name + author), `loadBranches` (for-each-ref), `loadStashes` (+ per-stash files), `loadHistory` (log + per-commit files + relativeDate), `loadDiff` (working/commit/stash) → Task 1 ✓
- Actions: stage/unstage/discard(untracked→clean)/commit(returns new Commit)/pull/push/fetch(SyncResult via re-status)/switchBranch/apply/pop/drop → Task 2 ✓
- Integration tests against temp real repos (reads + actions) → Tasks 1–2 ✓
- `GitWorkbenchLiveDemo` (real repo + `--shot`) → Task 3 ✓
- **Notes/limitations:** pull/push/fetch require a configured remote (error otherwise — surfaced as a toast); the `--name-status -z` rename handling keeps the new path; commit/stash file lists are fetched per item (fine for demo-sized history). Untracked files report 0 counts (no diff). These match the design spec's deferred edges.

**2. Placeholder scan:** Complete code in every step. Integration tests build real temp repos with `git`; the live-demo `--shot` step is a real capture against this repository.

**3. Type/signature consistency:** `CLIGitProvider: GitWorkbenchProvider` implements every protocol method (`GitWorkbenchDataSource` reads in Task 1, `GitWorkbenchActionHandler` in Task 2). Uses the Plan 9 parsers (`StatusParser`/`NumstatParser`/`DiffParser`/`LogParser`/`RefParser`/`StashParser`), `GitRunner.output`, `GitError`. Produces core model types. The live demo uses `GitWorkbenchStore(provider:)` + `GitWorkbenchView(store:)` (public). `Commit`/`Stash` `files`/`relativeDate` are `var` (mutated when attaching). `FileChange(id:path:status:isStaged:additions:deletions:)` used consistently.
