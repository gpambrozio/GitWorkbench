import Foundation
import GitWorkbench

/// A `GitWorkbenchProvider` backed by the system `git` CLI. Read side here; actions in an extension.
public struct CLIGitProvider: GitWorkbenchProvider {
    let runner: GitRunner
    /// When true (the default), `repositoryChanges()` vends an FSEvents-backed stream so the
    /// store auto-reloads on external edits/commits. Set false to opt out (e.g. a host that
    /// drives its own refresh).
    let watchesFileSystem: Bool
    static let logFormat = "%H%x1f%h%x1f%an%x1f%ae%x1f%aI%x1f%cI%x1f%P%x1f%D%x1f%s%x1f%b%x1e"

    public init(repositoryURL: URL, gitPath: String = "/usr/bin/git", watchesFileSystem: Bool = true) {
        self.runner = GitRunner(repositoryURL: repositoryURL, gitPath: gitPath)
        self.watchesFileSystem = watchesFileSystem
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

    /// FSEvents-backed change stream so the store reloads on external edits/commits/branch
    /// switches. The watcher is owned by the stream and torn down when the consumer stops
    /// (the store cancels its subscription on deinit). `nil` when watching is opted out.
    public func repositoryChanges() -> AsyncStream<Void>? {
        guard watchesFileSystem else { return nil }
        let url = runner.repositoryURL
        // Coalesce a backlog into a single reload: if changes arrive while the store is mid-reload,
        // we only need to know "something changed", not how many times.
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let watcher = RepositoryWatcher(url: url) { continuation.yield(()) }
            watcher.start()
            continuation.onTermination = { _ in watcher.stop() }
        }
    }

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

    public func loadHistory(of ref: String?, before: Commit.ID?, limit: Int) async throws -> [Commit] {
        var args = ["log", "--format=\(Self.logFormat)", "--max-count=\(limit)"]
        // Page older than `before` with `--skip=1 <before>` rather than `<before>^`: equivalent for
        // interior commits, but returns an empty page (exit 0) at the root commit instead of
        // `<sha>^` failing with "unknown revision" (exit 128) and throwing. The paging SHA already pins
        // the position, so `ref` only applies to the first page (else `git log` defaults to HEAD).
        if let before { args += ["--skip=1", "\(before)"] }
        else if let ref { args.append(ref) }
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
            if !staged, request.file.status == .untracked {
                text = try await untrackedDiffText(request.file.path)
            } else {
                let args = staged ? ["diff", "--cached", "--", request.file.path]
                                  : ["diff", "--", request.file.path]
                text = try await runner.output(args).text
            }
        case .commit(let id):
            text = try await runner.output(["show", id, "--format=", "--", request.file.path]).text
        case .stash(let id):
            // `git stash show` does NOT accept a pathspec — `stash show -p <id> -- <path>` fails with
            // "Too many revisions specified" (it reads <path> as a second revision). A stash entry is
            // a commit, so diff its base (^1) against its tip for the one file, like `git show` does.
            text = try await runner.output(["diff", "\(id)^", id, "--", request.file.path]).text
        }
        return DiffParser.parse(unifiedDiff: text, file: request.file)
    }

    /// An untracked file has no tracked diff, so `git diff -- <path>` is empty. Show its whole
    /// content as additions via `git diff --no-index /dev/null <path>` — which exits 1 when the
    /// files differ (always, here), so accept exit ≤ 1 and only throw on a real error.
    private func untrackedDiffText(_ path: String) async throws -> String {
        guard !path.hasSuffix("/") else { return "" }   // an untracked directory has no single-file diff
        let result = try await runner.run(["diff", "--no-index", "/dev/null", path])
        guard result.exitCode <= 1 else {
            throw GitError.commandFailed(arguments: ["diff", "--no-index", path],
                                         code: result.exitCode, stderr: result.stderr)
        }
        return result.text
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
