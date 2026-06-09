import Foundation

/// Errors surfaced by the in-memory mock.
public enum MockGitError: Error, LocalizedError, Equatable {
    case noDiff(String)

    public var errorDescription: String? {
        switch self {
        case .noDiff(let path): return "No diff available for \(path)."
        }
    }
}

/// In-memory `GitWorkbenchProvider` backed by `Fixtures`. Mutates its own copy so the
/// demo/preview/tests can exercise every action. `actor`-isolated for safe mutation.
public actor MockGitProvider: GitWorkbenchProvider {
    private var status: RepositoryStatus
    private var commits: [Commit]
    private var stashes: [Stash]
    private var branches: [Branch]
    private let delay: Duration

    /// `delay` is the artificial latency per call (default 700ms; pass `.zero` in tests).
    public init(delay: Duration = .milliseconds(700)) {
        self.status = Fixtures.repositoryStatus
        self.commits = Fixtures.commits
        self.stashes = Fixtures.stashes
        self.branches = Fixtures.branches
        self.delay = delay
    }

    private func pause() async {
        if delay != .zero { try? await Task.sleep(for: delay) }
    }

    // MARK: GitWorkbenchDataSource

    public func loadStatus() async throws -> RepositoryStatus {
        await pause()
        return status
    }

    public func loadHistory(of ref: String?, before: Commit.ID?, limit: Int) async throws -> [Commit] {
        _ = ref   // the mock has a single fixture history; branch ref doesn't change it
        await pause()
        let start: Int
        if let before, let idx = commits.firstIndex(where: { $0.id == before }) {
            start = idx + 1
        } else {
            start = 0
        }
        guard start < commits.count else { return [] }
        return Array(commits[start..<min(start + limit, commits.count)])
    }

    public func loadStashes() async throws -> [Stash] {
        await pause()
        return stashes
    }

    public func loadBranches() async throws -> [Branch] {
        await pause()
        return branches
    }

    public func loadDiff(_ request: DiffRequest) async throws -> FileDiff {
        await pause()
        guard let diff = FixtureDiffs.diff(for: request.file, context: request.context) else {
            throw MockGitError.noDiff(request.file.path)
        }
        return diff
    }

}

extension MockGitProvider {

    public func stage(_ files: [FileChange]) async throws {
        await pause()
        setStaged(files.map(\.path), to: true)
    }

    public func unstage(_ files: [FileChange]) async throws {
        await pause()
        setStaged(files.map(\.path), to: false)
    }

    public func discard(_ file: FileChange) async throws {
        await pause()
        status.files.removeAll { $0.path == file.path }
    }

    public func commit(message: String, staged: [FileChange]) async throws -> Commit {
        await pause()
        let stagedPaths = Set(staged.map(\.path))
        status.files.removeAll { stagedPaths.contains($0.path) }
        status.ahead += 1

        let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let summary = lines.first ?? ""
        let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let new = Commit(
            id: "mock\(commits.count)", shortSHA: "mock\(commits.count)",
            summary: summary, body: body,
            authorName: status.author.name, authorEmail: "you@example.com",
            authorInitials: status.author.initials, date: "Just now", relativeDate: "moments ago",
            refs: [.head], parents: commits.first.map { [$0.shortSHA] } ?? [],
            files: staged
        )
        commits.insert(new, at: 0)
        return new
    }

    public func pull() async throws -> SyncResult {
        await pause()
        let pulled = status.behind
        // Simulate the fetched commits arriving at the tip of the current branch so the
        // History view has something new to show after a pull.
        for _ in 0..<pulled {
            let new = Commit(
                id: "pulled\(commits.count)", shortSHA: "pulled\(commits.count)",
                summary: "Pulled from origin", body: "",
                authorName: "Origin", authorEmail: "origin@example.com",
                authorInitials: "OR", date: "Just now", relativeDate: "moments ago",
                refs: [.head], parents: commits.first.map { [$0.shortSHA] } ?? [],
                files: []
            )
            commits.insert(new, at: 0)
        }
        status.behind = 0
        return SyncResult(ahead: status.ahead, behind: 0,
                          message: pulled > 0 ? "Pulled \(pulled) commit(s) from origin" : "Already up to date with origin")
    }

    public func push() async throws -> SyncResult {
        await pause()
        let pushed = status.ahead
        status.ahead = 0
        return SyncResult(ahead: 0, behind: status.behind,
                          message: pushed > 0 ? "Pushed \(pushed) commit(s) to origin" : "Everything up to date")
    }

    public func fetch() async throws -> SyncResult {
        await pause()
        return SyncResult(ahead: status.ahead, behind: status.behind, message: "Up to date with origin")
    }

    public func switchBranch(to branch: Branch) async throws {
        await pause()
        status.currentBranch = branch.name
        status.upstream = branch.upstream
        branches = branches.map {
            Branch(name: $0.name, isCurrent: $0.name == branch.name, upstream: $0.upstream)
        }
    }

    public func applyStash(_ stash: Stash) async throws { await pause() }   // keeps the stash

    public func popStash(_ stash: Stash) async throws {
        await pause()
        stashes.removeAll { $0.id == stash.id }
    }

    public func dropStash(_ stash: Stash) async throws {
        await pause()
        stashes.removeAll { $0.id == stash.id }
    }

    // MARK: Helpers

    private func setStaged(_ paths: [String], to staged: Bool) {
        let set = Set(paths)
        status.files = status.files.map { f in
            guard set.contains(f.path) else { return f }
            return FileChange(id: f.id, path: f.path, status: f.status,
                              isStaged: staged, additions: f.additions, deletions: f.deletions)
        }
    }
}
