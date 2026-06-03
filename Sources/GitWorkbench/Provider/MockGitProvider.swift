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

    public func loadHistory(before: Commit.ID?, limit: Int) async throws -> [Commit] {
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

    // MARK: GitWorkbenchActionHandler — implemented in extension below (Task 5)

    public func stage(_ files: [FileChange]) async throws { fatalError("stub") }
    public func unstage(_ files: [FileChange]) async throws { fatalError("stub") }
    public func discard(_ file: FileChange) async throws { fatalError("stub") }
    public func commit(message: String, staged: [FileChange]) async throws -> Commit { fatalError("stub") }
    public func pull() async throws -> SyncResult { fatalError("stub") }
    public func push() async throws -> SyncResult { fatalError("stub") }
    public func fetch() async throws -> SyncResult { fatalError("stub") }
    public func switchBranch(to branch: Branch) async throws { fatalError("stub") }
    public func applyStash(_ stash: Stash) async throws { fatalError("stub") }
    public func popStash(_ stash: Stash) async throws { fatalError("stub") }
    public func dropStash(_ stash: Stash) async throws { fatalError("stub") }
}
