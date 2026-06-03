# GitWorkbenchGitKit — Git Layer (Runner + Parsers) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Build the `GitWorkbenchGitKit` target's git-execution + parsing layer: a `GitRunner` (Foundation `Process` wrapper, deadlock-safe), `GitError`, and pure parsers that turn git's machine-stable output into the core's model types — `StatusParser`, `NumstatParser`, `DiffParser`, `LogParser`, `RefParser`, `StashParser` — each unit-tested against captured git output.

**Architecture:** Plan 9 of the program (the core component is complete on `main`). GitKit is a new **library target in the root package** (`Sources/GitWorkbenchGitKit/`) depending only on `GitWorkbench` (for the models + provider protocols) — **no third-party dependencies** (Foundation `Process`, not swift-subprocess). The core `GitWorkbench` library is unaffected and stays zero-dep. This plan delivers the runner + parsers (the testable logic); Plan 10 wires them into `CLIGitProvider` and a live demo. (Deviations from design spec §6: Foundation `Process` instead of swift-subprocess; root-package target instead of a nested package — both keep the "shell out to git" strategy + clean core, with less risk.)

**Tech Stack:** Swift 6, SwiftPM, macOS 15+, XCTest, Foundation. No third-party deps.

**Conventions:** Parsers are pure functions over captured git output (deterministic tests). Command formats use NUL/field separators for safe parsing. Handle the common cases robustly (modified/added/deleted/untracked/staged-unstaged, standard hunks, commits, branches, stashes); note edge cases (complex renames, binary, quoting) where deferred. Run from repo root; execution on `feat/gitkit-layer`.

---

### Task 1: Package target + GitRunner + GitError

**Files:**
- Modify: `Package.swift` (add the `GitWorkbenchGitKit` target + test target + product)
- Create: `Sources/GitWorkbenchGitKit/GitRunner.swift`
- Create: `Sources/GitWorkbenchGitKit/GitError.swift`

- [ ] **Step 1: Add the target to `Package.swift`**

In `Package.swift`, add to `products:` (after the demo product):

```swift
        .library(name: "GitWorkbenchGitKit", targets: ["GitWorkbenchGitKit"]),
```

and add to `targets:` (after the `GitWorkbench` target):

```swift
        .target(
            name: "GitWorkbenchGitKit",
            dependencies: ["GitWorkbench"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GitWorkbenchGitKitTests",
            dependencies: ["GitWorkbenchGitKit", "GitWorkbench"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
```

- [ ] **Step 2: Write `GitError.swift`**

```swift
import Foundation

/// Errors from running git.
public enum GitError: Error, LocalizedError, Equatable {
    case gitNotFound(String)
    case notARepository(String)
    case commandFailed(arguments: [String], code: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .gitNotFound(let path):
            return "git executable not found at \(path)."
        case .notARepository(let path):
            return "\(path) is not a git repository."
        case .commandFailed(_, _, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().contains("rejected") || trimmed.lowercased().contains("non-fast-forward") {
                return "Push rejected \u{2014} pull first"
            }
            return trimmed.isEmpty ? "git command failed." : trimmed
        }
    }
}
```

- [ ] **Step 3: Write `GitRunner.swift`**

```swift
import Foundation

/// The result of a git invocation.
public struct GitOutput: Sendable {
    public var stdout: Data
    public var stderr: String
    public var exitCode: Int32
    public var text: String { String(decoding: stdout, as: UTF8.self) }
}

/// Runs `git` in a repository directory via Foundation `Process`. Drains stdout/stderr
/// concurrently (no pipe-buffer deadlock). `Sendable`: holds only immutable config.
public struct GitRunner: Sendable {
    public let repositoryURL: URL
    public let gitPath: String

    public init(repositoryURL: URL, gitPath: String = "/usr/bin/git") {
        self.repositoryURL = repositoryURL
        self.gitPath = gitPath
    }

    /// Runs git with the given arguments and returns the raw output (any exit code).
    public func run(_ arguments: [String]) async throws -> GitOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["-C", repositoryURL.path] + arguments
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do { try process.run() }
        catch { throw GitError.gitNotFound(gitPath) }

        async let outData = Self.readToEnd(outPipe.fileHandleForReading)
        async let errData = Self.readToEnd(errPipe.fileHandleForReading)
        let (out, err) = await (outData, errData)
        process.waitUntilExit()

        return GitOutput(stdout: out,
                         stderr: String(decoding: err, as: UTF8.self),
                         exitCode: process.terminationStatus)
    }

    /// Runs git and throws `GitError.commandFailed` on a non-zero exit; otherwise returns the output.
    public func output(_ arguments: [String]) async throws -> GitOutput {
        let result = try await run(arguments)
        guard result.exitCode == 0 else {
            throw GitError.commandFailed(arguments: arguments, code: result.exitCode, stderr: result.stderr)
        }
        return result
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = handle.readDataToEndOfFile()
                continuation.resume(returning: data)
            }
        }
    }
}
```

- [ ] **Step 4: Build & smoke-test**

Create `Tests/GitWorkbenchGitKitTests/GitRunnerTests.swift`:

```swift
import XCTest
@testable import GitWorkbenchGitKit

final class GitRunnerTests: XCTestCase {
    func test_runsGitVersionInThisRepo() async throws {
        // This repo is a real git repo; `git -C . rev-parse --is-inside-work-tree` → "true".
        let runner = GitRunner(repositoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let result = try await runner.output(["rev-parse", "--is-inside-work-tree"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.text.trimmingCharacters(in: .whitespacesAndNewlines), "true")
    }

    func test_nonzeroExitThrows() async {
        let runner = GitRunner(repositoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        do {
            _ = try await runner.output(["cat-file", "-e", "0000000000000000000000000000000000000000"])
            XCTFail("expected failure")
        } catch let error as GitError {
            if case .commandFailed = error {} else { XCTFail("wrong error: \(error)") }
        } catch { XCTFail("wrong error type") }
    }
}
```

Run: `swift build && swift test --filter GitRunnerTests`
Expected: build succeeds; both tests pass (this is run inside the repo, so `git` works).

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/GitWorkbenchGitKit Tests/GitWorkbenchGitKitTests/GitRunnerTests.swift
git commit -m "GitKit: add target, GitError, and GitRunner (Foundation Process)"
```

---

### Task 2: StatusParser + NumstatParser

**Files:**
- Create: `Sources/GitWorkbenchGitKit/Parsers/StatusParser.swift`
- Create: `Sources/GitWorkbenchGitKit/Parsers/NumstatParser.swift`
- Test: `Tests/GitWorkbenchGitKitTests/StatusParserTests.swift`

> `StatusParser` parses `git status --porcelain=v2 -z --branch` into branch info + files. A file with both staged (X) and unstaged (Y) changes emits TWO `FileChange`s with suffixed ids (`path:staged` / `path:unstaged`) per design spec §6.3. `NumstatParser` parses `git diff --numstat -z` into per-path (additions, deletions); the provider merges those counts in later (Plan 10).

- [ ] **Step 1: Write the failing tests**

`Tests/GitWorkbenchGitKitTests/StatusParserTests.swift`:

```swift
import XCTest
@testable import GitWorkbenchGitKit
import GitWorkbench

final class StatusParserTests: XCTestCase {
    // Porcelain v2 -z --branch: NUL-separated records. (Use \u{0} between records.)
    private let sample = [
        "# branch.oid abc123",
        "# branch.head feat/x",
        "# branch.upstream origin/feat/x",
        "# branch.ab +2 -1",
        "1 M. N... 100644 100644 100644 h1 h2 src/staged.swift",
        "1 .M N... 100644 100644 100644 h1 h2 src/unstaged.swift",
        "1 MM N... 100644 100644 100644 h1 h2 src/both.swift",
        "1 A. N... 000000 100644 100644 h1 h2 added.swift",
        "1 .D N... 100644 100644 100644 h1 h2 gone.swift",
        "? untracked.txt",
        "u UU N... 100644 100644 100644 100644 h1 h2 h3 conflict.swift",
    ].joined(separator: "\u{0}") + "\u{0}"

    func test_parsesBranchInfo() {
        let result = StatusParser.parse(porcelain: sample)
        XCTAssertEqual(result.branch, "feat/x")
        XCTAssertEqual(result.upstream, "origin/feat/x")
        XCTAssertEqual(result.ahead, 2)
        XCTAssertEqual(result.behind, 1)
    }

    func test_partitionsStagedAndUnstaged() {
        let files = StatusParser.parse(porcelain: sample).files
        // staged.swift (staged, M), both.swift:staged (staged, M), added.swift (staged, A)
        let staged = files.filter(\.isStaged).map(\.path).sorted()
        XCTAssertEqual(staged, ["added.swift", "src/both.swift", "src/staged.swift"])
        // unstaged: unstaged.swift, both.swift:unstaged, gone.swift, untracked.txt, conflict.swift
        let unstaged = files.filter { !$0.isStaged }.map(\.path).sorted()
        XCTAssertEqual(unstaged, ["conflict.swift", "gone.swift", "src/both.swift", "src/unstaged.swift", "untracked.txt"])
    }

    func test_bothModifiedFileGetsSuffixedIDs() {
        let files = StatusParser.parse(porcelain: sample).files.filter { $0.path == "src/both.swift" }
        XCTAssertEqual(Set(files.map(\.id)), ["src/both.swift:staged", "src/both.swift:unstaged"])
    }

    func test_mapsStatusCodes() {
        let files = StatusParser.parse(porcelain: sample).files
        func status(_ path: String, staged: Bool) -> FileStatus? {
            files.first { $0.path == path && $0.isStaged == staged }?.status
        }
        XCTAssertEqual(status("added.swift", staged: true), .added)
        XCTAssertEqual(status("gone.swift", staged: false), .deleted)
        XCTAssertEqual(status("untracked.txt", staged: false), .untracked)
        XCTAssertEqual(status("conflict.swift", staged: false), .conflicted)
    }

    func test_numstatParsesCounts() {
        let numstat = ["24\t6\tsrc/a.swift", "0\t18\tsrc/b.swift", "-\t-\tbinary.png"].joined(separator: "\u{0}") + "\u{0}"
        let counts = NumstatParser.parse(numstat)
        XCTAssertEqual(counts["src/a.swift"]?.additions, 24)
        XCTAssertEqual(counts["src/a.swift"]?.deletions, 6)
        XCTAssertEqual(counts["src/b.swift"]?.deletions, 18)
        XCTAssertEqual(counts["binary.png"]?.additions, 0)   // "-" (binary) → 0
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter StatusParserTests`
Expected: FAIL — `StatusParser`/`NumstatParser` undefined.

- [ ] **Step 3: Write `NumstatParser.swift`**

```swift
import Foundation

/// Parses `git diff --numstat -z` into per-path (additions, deletions). "-" counts (binary) → 0.
public enum NumstatParser {
    public static func parse(_ output: String) -> [String: (additions: Int, deletions: Int)] {
        var result: [String: (additions: Int, deletions: Int)] = [:]
        for record in output.split(separator: "\u{0}", omittingEmptySubsequences: true) {
            let parts = record.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { continue }
            let add = Int(parts[0]) ?? 0      // "-" → nil → 0
            let del = Int(parts[1]) ?? 0
            result[parts[2]] = (add, del)
        }
        return result
    }
}
```

- [ ] **Step 4: Write `StatusParser.swift`**

```swift
import Foundation
import GitWorkbench

public enum StatusParser {
    public struct Result {
        public var branch: String
        public var upstream: String?
        public var ahead: Int
        public var behind: Int
        public var files: [FileChange]
    }

    public static func parse(porcelain output: String) -> Result {
        var branch = "", upstream: String? = nil, ahead = 0, behind = 0
        var files: [FileChange] = []
        let records = output.split(separator: "\u{0}", omittingEmptySubsequences: true).map(String.init)

        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            if record.hasPrefix("# branch.head ") {
                branch = String(record.dropFirst("# branch.head ".count))
            } else if record.hasPrefix("# branch.upstream ") {
                upstream = String(record.dropFirst("# branch.upstream ".count))
            } else if record.hasPrefix("# branch.ab ") {
                let ab = record.dropFirst("# branch.ab ".count).split(separator: " ")
                for token in ab {
                    if token.hasPrefix("+") { ahead = Int(token.dropFirst()) ?? 0 }
                    else if token.hasPrefix("-") { behind = Int(token.dropFirst()) ?? 0 }
                }
            } else if record.hasPrefix("1 ") {
                files.append(contentsOf: ordinary(record))
            } else if record.hasPrefix("2 ") {
                files.append(contentsOf: ordinary(record))   // rename: treat by its new path
                index += 1                                    // skip the original-path record
            } else if record.hasPrefix("? ") {
                files.append(FileChange(path: String(record.dropFirst(2)), status: .untracked, isStaged: false))
            } else if record.hasPrefix("u ") {
                if let path = record.split(separator: " ").last.map(String.init) {
                    files.append(FileChange(path: path, status: .conflicted, isStaged: false))
                }
            }
        }
        return Result(branch: branch, upstream: upstream, ahead: ahead, behind: behind, files: files)
    }

    /// A `1`/`2` entry: `<type> <XY> <sub> <mH> <mI> <mW> <hH> <hI> [<score>] <path>`.
    private static func ordinary(_ record: String) -> [FileChange] {
        let fields = record.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 9 else { return [] }
        let xy = Array(fields[1])
        guard xy.count == 2 else { return [] }
        // path is everything after the 8th field (type=0..path). For `1`, fields 0..7 are metadata, 8+ path.
        // For `2`, an extra score field shifts path to 9+. Detect by type.
        let pathStartField = record.hasPrefix("2 ") ? 9 : 8
        guard fields.count > pathStartField else { return [] }
        let path = fields[pathStartField...].joined(separator: " ")

        var out: [FileChange] = []
        if xy[0] != "." {
            out.append(FileChange(id: out.isEmpty && xy[1] == "." ? path : "\(path):staged",
                                  path: path, status: status(for: xy[0]), isStaged: true))
        }
        if xy[1] != "." {
            out.append(FileChange(id: xy[0] == "." ? path : "\(path):unstaged",
                                  path: path, status: status(for: xy[1]), isStaged: false))
        }
        return out
    }

    private static func status(for code: Character) -> FileStatus {
        switch code {
        case "A": return .added
        case "D": return .deleted
        case "R", "C": return .renamed
        case "U": return .conflicted
        default: return .modified
        }
    }
}
```

- [ ] **Step 5: Run to verify pass + commit**

Run: `swift test --filter StatusParserTests`
Expected: PASS (all five). If `test_bothModifiedFileGetsSuffixedIDs` fails, the id-suffix branch is wrong — both X and Y are non-dot, so both ids must be suffixed.

```bash
git add Sources/GitWorkbenchGitKit/Parsers/StatusParser.swift Sources/GitWorkbenchGitKit/Parsers/NumstatParser.swift Tests/GitWorkbenchGitKitTests/StatusParserTests.swift
git commit -m "GitKit: add StatusParser (porcelain v2) and NumstatParser"
```

---

### Task 3: DiffParser

**Files:**
- Create: `Sources/GitWorkbenchGitKit/Parsers/DiffParser.swift`
- Test: `Tests/GitWorkbenchGitKitTests/DiffParserTests.swift`

> Parses `git diff` unified output into a `FileDiff` (hunks of `DiffLine`s), reusing the core's `DiffBuilder` line-number logic. Detects binary diffs. Skips the file header lines (`diff --git`, `index`, `---`, `+++`).

- [ ] **Step 1: Write the failing test**

`Tests/GitWorkbenchGitKitTests/DiffParserTests.swift`:

```swift
import XCTest
@testable import GitWorkbenchGitKit
import GitWorkbench

final class DiffParserTests: XCTestCase {
    private let sample = """
    diff --git a/src/a.swift b/src/a.swift
    index 1111111..2222222 100644
    --- a/src/a.swift
    +++ b/src/a.swift
    @@ -1,3 +1,4 @@
     import Foundation
    -let x = 1
    +let x = 2
    +let y = 3
     // end
    @@ -10,2 +11,2 @@
    -old
    +new
    """

    func test_parsesHunksAndLines() {
        let file = FileChange(path: "src/a.swift", status: .modified)
        let diff = DiffParser.parse(unifiedDiff: sample, file: file)
        XCTAssertEqual(diff.hunks.count, 2)
        XCTAssertFalse(diff.isBinary)
        XCTAssertTrue(diff.hunks[0].header.hasPrefix("@@ -1,"))
        let kinds = diff.hunks[0].lines.map(\.kind)
        XCTAssertEqual(kinds, [.context, .deletion, .addition, .addition, .context])
        // first context line: old 1 / new 1; first addition: new 2 (after the deletion at old 2)
        XCTAssertEqual(diff.hunks[0].lines[0].oldNumber, 1)
        XCTAssertEqual(diff.hunks[0].lines[1].oldNumber, 2)   // deletion advances old
        XCTAssertEqual(diff.hunks[0].lines[2].newNumber, 2)   // addition advances new
        XCTAssertEqual(diff.hunks[0].lines.map(\.text)[1], "let x = 1")
    }

    func test_detectsBinary() {
        let bin = "diff --git a/x.png b/x.png\nBinary files a/x.png and b/x.png differ\n"
        let diff = DiffParser.parse(unifiedDiff: bin, file: FileChange(path: "x.png", status: .modified))
        XCTAssertTrue(diff.isBinary)
        XCTAssertTrue(diff.hunks.isEmpty)
    }

    func test_emptyDiffYieldsNoHunks() {
        let diff = DiffParser.parse(unifiedDiff: "", file: FileChange(path: "x", status: .modified))
        XCTAssertTrue(diff.hunks.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter DiffParserTests`
Expected: FAIL — `DiffParser` undefined.

- [ ] **Step 3: Write `DiffParser.swift`**

```swift
import Foundation
import GitWorkbench

/// Parses unified `git diff` output into a `FileDiff` using the core `DiffBuilder`.
public enum DiffParser {
    public static func parse(unifiedDiff text: String, file: FileChange) -> FileDiff {
        if text.contains("\nBinary files ") || text.hasPrefix("Binary files ") {
            return FileDiff(file: file, hunks: [], isBinary: true)
        }

        var hunks: [DiffHunk] = []
        var oldStart = 0, newStart = 0
        var rawLines: [String] = []
        var inHunk = false

        func flush() {
            guard inHunk else { return }
            hunks.append(DiffBuilder.hunk(oldStart: oldStart, newStart: newStart, rawLines))
            rawLines = []
            inHunk = false
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("@@") {
                flush()
                (oldStart, newStart) = parseHunkStarts(line)
                inHunk = true
            } else if inHunk {
                // Diff body lines start with '+', '-', or ' '. Skip "\ No newline at end of file".
                if line.hasPrefix("\\") { continue }
                if line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ") {
                    rawLines.append(line)
                } else if line.isEmpty {
                    rawLines.append(" ")   // a bare empty line in the body is a blank context line
                } else {
                    // a new file header (diff --git ...) ends the hunk
                    flush()
                }
            }
        }
        flush()
        return FileDiff(file: file, hunks: hunks, isBinary: false)
    }

    /// Parses `@@ -<oldStart>[,len] +<newStart>[,len] @@ ...` → (oldStart, newStart).
    private static func parseHunkStarts(_ header: String) -> (Int, Int) {
        // Find the "-A,B +C,D" portion between the first "@@" pairs.
        let parts = header.split(separator: " ")
        var oldStart = 0, newStart = 0
        for part in parts {
            if part.hasPrefix("-") {
                oldStart = Int(part.dropFirst().split(separator: ",").first ?? "0") ?? 0
            } else if part.hasPrefix("+") {
                newStart = Int(part.dropFirst().split(separator: ",").first ?? "0") ?? 0
            }
        }
        return (oldStart, newStart)
    }
}
```

- [ ] **Step 4: Run to verify pass + commit**

Run: `swift test --filter DiffParserTests`
Expected: PASS (all three).

```bash
git add Sources/GitWorkbenchGitKit/Parsers/DiffParser.swift Tests/GitWorkbenchGitKitTests/DiffParserTests.swift
git commit -m "GitKit: add DiffParser (unified diff -> FileDiff via DiffBuilder)"
```

---

### Task 4: LogParser, RefParser, StashParser

**Files:**
- Create: `Sources/GitWorkbenchGitKit/Parsers/LogParser.swift`
- Create: `Sources/GitWorkbenchGitKit/Parsers/RefParser.swift`
- Create: `Sources/GitWorkbenchGitKit/Parsers/StashParser.swift`
- Test: `Tests/GitWorkbenchGitKitTests/LogRefStashParserTests.swift`

> `LogParser` parses a field-delimited `git log` (one record per commit) into `[Commit]` (refs from `%D`, initials derived). `RefParser` parses `for-each-ref` lines into `[Branch]`. `StashParser` parses `stash list` lines into `[Stash]` (without files — the provider loads files per-stash on demand in Plan 10).

These use explicit separators so parsing is unambiguous:
- Log record: `%H%x1f%h%x1f%an%x1f%ae%x1f%aI%x1f%cI%x1f%P%x1f%D%x1f%s%x1f%b%x1e` (field sep `\u{1f}`, record sep `\u{1e}`).
- Ref: `%(refname:short)%1f%(upstream:short)%1f%(HEAD)`.
- Stash: `%gd%1f%s%1f%cr` (selector, subject, relative date) — git's `stash list --format`.

- [ ] **Step 1: Write the failing tests**

`Tests/GitWorkbenchGitKitTests/LogRefStashParserTests.swift`:

```swift
import XCTest
@testable import GitWorkbenchGitKit
import GitWorkbench

final class LogRefStashParserTests: XCTestCase {
    func test_logParsesCommits() {
        let F = "\u{1f}", R = "\u{1e}"
        let record = ["9f2c1a4e7b3","9f2c1a4","Gustavo Ambrozio","g@x.dev","2026-06-01T09:42:00-03:00",
                      "2026-06-01T09:42:00-03:00","3b8e7d2f1a9","HEAD -> feat/x, tag: v1.0, origin/feat/x",
                      "Add the thing","body line 1\nbody line 2"].joined(separator: F)
        let commits = LogParser.parse(record + R)
        XCTAssertEqual(commits.count, 1)
        let c = commits[0]
        XCTAssertEqual(c.shortSHA, "9f2c1a4")
        XCTAssertEqual(c.summary, "Add the thing")
        XCTAssertEqual(c.authorName, "Gustavo Ambrozio")
        XCTAssertEqual(c.authorInitials, "GA")
        XCTAssertEqual(c.parents, ["3b8e7d2f1a9"])
        XCTAssertTrue(c.refs.contains(.head))
        XCTAssertTrue(c.refs.contains(.branch("feat/x")))
        XCTAssertTrue(c.refs.contains(.tag("v1.0")))
        XCTAssertTrue(c.body.contains("body line 1"))
    }

    func test_refParsesBranches() {
        let F = "\u{1f}"
        let lines = ["main\(F)origin/main\(F)*", "feat/x\(F)origin/feat/x\(F)", "dev\(F)\(F)"]
        let branches = RefParser.parse(lines.joined(separator: "\n"))
        XCTAssertEqual(branches.map(\.name), ["main", "feat/x", "dev"])
        XCTAssertEqual(branches.first(where: { $0.name == "main" })?.upstream, "origin/main")
        XCTAssertTrue(branches.first(where: { $0.name == "main" })!.isCurrent)
        XCTAssertNil(branches.first(where: { $0.name == "dev" })?.upstream)
    }

    func test_stashParsesEntries() {
        let F = "\u{1f}"
        let lines = ["stash@{0}\(F)WIP: tune retry delays\(F)40 minutes ago",
                     "stash@{1}\(F)experiment\(F)2 days ago"]
        let stashes = StashParser.parse(lines.joined(separator: "\n"), branch: "feat/x")
        XCTAssertEqual(stashes.map(\.ref), ["stash@{0}", "stash@{1}"])
        XCTAssertEqual(stashes[0].message, "WIP: tune retry delays")
        XCTAssertEqual(stashes[0].relativeDate, "40 minutes ago")
        XCTAssertEqual(stashes[0].id, "stash@{0}")
    }

    func test_initialsHelper() {
        XCTAssertEqual(LogParser.initials(for: "Gustavo Ambrozio"), "GA")
        XCTAssertEqual(LogParser.initials(for: "madonna"), "M")
        XCTAssertEqual(LogParser.initials(for: ""), "?")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter LogRefStashParserTests`
Expected: FAIL — parsers undefined.

- [ ] **Step 3: Write `LogParser.swift`**

```swift
import Foundation
import GitWorkbench

/// Parses field/record-delimited `git log` output into `[Commit]`.
/// Record fields: H, h, an, ae, aI, cI, P, D, s, b  (sep `\u{1f}`); records sep `\u{1e}`.
public enum LogParser {
    public static func parse(_ output: String) -> [Commit] {
        output.split(separator: "\u{1e}", omittingEmptySubsequences: true).compactMap { rawRecord -> Commit? in
            let fields = rawRecord
                .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
                .split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 10 else { return nil }
            let parents = fields[6].split(separator: " ").map(String.init).filter { !$0.isEmpty }
            return Commit(
                id: fields[0], shortSHA: fields[1], summary: fields[8], body: fields[9],
                authorName: fields[2], authorEmail: fields[3], authorInitials: initials(for: fields[2]),
                date: displayDate(fields[5]), relativeDate: "", refs: refs(from: fields[7]),
                parents: parents, files: []
            )
        }
    }

    /// Parses git's `%D` decoration string into typed refs (HEAD, branches, tags).
    static func refs(from decoration: String) -> [CommitRef] {
        var result: [CommitRef] = []
        for part in decoration.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
            if part == "HEAD" || part.hasPrefix("HEAD -> ") {
                result.append(.head)
                if let arrow = part.range(of: "HEAD -> ") {
                    result.append(.branch(String(part[arrow.upperBound...])))
                }
            } else if part.hasPrefix("tag: ") {
                result.append(.tag(String(part.dropFirst("tag: ".count))))
            } else if !part.contains("/") {       // a local branch (skip remote-tracking like origin/x)
                result.append(.branch(part))
            }
        }
        return result
    }

    static func initials(for name: String) -> String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        if words.isEmpty { return "?" }
        if words.count == 1 { return String(words[0].prefix(1)).uppercased() }
        return (String(words[0].prefix(1)) + String(words[words.count - 1].prefix(1))).uppercased()
    }

    private static func displayDate(_ iso: String) -> String { String(iso.prefix(10)) }  // YYYY-MM-DD
}
```

- [ ] **Step 4: Write `RefParser.swift`**

```swift
import Foundation
import GitWorkbench

/// Parses `git for-each-ref --format='%(refname:short)\u{1f}%(upstream:short)\u{1f}%(HEAD)'` (one ref per line).
public enum RefParser {
    public static func parse(_ output: String) -> [Branch] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> Branch? in
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard let name = fields.first, !name.isEmpty else { return nil }
            let upstream = fields.count > 1 && !fields[1].isEmpty ? fields[1] : nil
            let isCurrent = fields.count > 2 && fields[2] == "*"
            return Branch(name: name, isCurrent: isCurrent, upstream: upstream)
        }
    }
}
```

- [ ] **Step 5: Write `StashParser.swift`**

```swift
import Foundation
import GitWorkbench

/// Parses `git stash list --format='%gd\u{1f}%s\u{1f}%cr'` (one stash per line). Files are loaded
/// separately by the provider (Plan 10); `branch` is the current branch for display.
public enum StashParser {
    public static func parse(_ output: String, branch: String) -> [Stash] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> Stash? in
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard let ref = fields.first, !ref.isEmpty else { return nil }
            let message = fields.count > 1 ? fields[1] : ""
            let relative = fields.count > 2 ? fields[2] : ""
            return Stash(id: ref, ref: ref, message: message, branch: branch, date: relative, relativeDate: relative, files: [])
        }
    }
}
```

- [ ] **Step 6: Run to verify pass + the full GitKit suite + commit**

Run: `swift test --filter GitWorkbenchGitKitTests`
Expected: PASS (all parser tests). Then `swift test` (the whole repo) is still green (the core's 67 + the new GitKit tests).

```bash
git add Sources/GitWorkbenchGitKit/Parsers/LogParser.swift Sources/GitWorkbenchGitKit/Parsers/RefParser.swift Sources/GitWorkbenchGitKit/Parsers/StashParser.swift Tests/GitWorkbenchGitKitTests/LogRefStashParserTests.swift
git commit -m "GitKit: add LogParser, RefParser, and StashParser"
```

---

## Self-Review

**1. Spec coverage (vs. design spec §6.1–6.3):**
- `GitRunner` (Foundation Process, deadlock-safe concurrent drain) + `GitError` (LocalizedError, push-rejected mapping) → Task 1 ✓
- `StatusParser` (porcelain v2: 1/2/?/u + branch headers; both-modified → suffixed ids per §6.3) + `NumstatParser` → Task 2 ✓
- `DiffParser` (unified → `FileDiff` via `DiffBuilder`; binary detection) → Task 3 ✓
- `LogParser` (field/record-delimited; `%D` → refs; initials) + `RefParser` + `StashParser` → Task 4 ✓
- **Deferred to Plan 10:** `CLIGitProvider` (wiring the protocol methods to git commands + merging numstat + loading commit/stash files), the live demo app, and integration tests against a real repo.
- **Edge cases noted:** complex renames (type 2) are mapped by their new path (origin path skipped); path quoting for unusual filenames isn't unescaped (the `-z`/field-separator formats avoid quoting for normal paths); binary diffs are flagged.

**2. Placeholder scan:** Complete code in every step. Tests use captured/synthesized git output with explicit separators (deterministic). `GitRunnerTests` runs real `git` inside this repo (which is a git repo).

**3. Type/signature consistency:** Parsers produce core model types (`FileChange(id:path:status:isStaged:)`, `Commit(...)`, `Branch(name:isCurrent:upstream:)`, `Stash(...)`, `FileDiff`/`DiffHunk` via `DiffBuilder.hunk`). `GitRunner.output(_:)`/`run(_:)` + `GitOutput.text` are the interface Plan 10's `CLIGitProvider` consumes. `GitError.commandFailed` is thrown on non-zero exits. `StatusParser.Result`/`NumstatParser` counts merge in Plan 10. All `import GitWorkbench` for the public models/`DiffBuilder`.
