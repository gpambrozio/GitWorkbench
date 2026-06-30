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
    private var remoteBranches: [RemoteBranch]
    private let delay: Duration

    /// `delay` is the artificial latency per call (default 700ms; pass `.zero` in tests).
    public init(delay: Duration = .milliseconds(700)) {
        self.status = Fixtures.repositoryStatus
        self.commits = Fixtures.commits
        self.stashes = Fixtures.stashes
        self.branches = Fixtures.branches
        self.remoteBranches = Fixtures.remoteBranches
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

    public func loadRemoteBranches() async throws -> [RemoteBranch] {
        await pause()
        return remoteBranches
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
        let new = makeCommit(summary: summary, body: body, files: staged)
        commits.insert(new, at: 0)
        return new
    }

    public func pull() async throws -> SyncResult {
        await pause()
        let pulled = status.behind
        // Simulate the fetched commits arriving at the tip of the current branch so the
        // History view has something new to show after a pull.
        for _ in 0..<pulled {
            let new = makeCommit(idPrefix: "pulled", summary: "Pulled from origin",
                                 authorName: "Origin", authorEmail: "origin@example.com", authorInitials: "OR")
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

    public func checkoutRemoteBranch(_ branch: RemoteBranch) async throws {
        await pause()
        // Create a local branch tracking the remote (if it doesn't exist yet), then make it current.
        status.currentBranch = branch.name
        status.upstream = branch.id
        if !branches.contains(where: { $0.name == branch.name }) {
            branches.append(Branch(name: branch.name, upstream: branch.id))
        }
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

    // MARK: History context-menu actions

    public func checkout(_ commit: Commit) async throws { await pause() }   // detaches HEAD; no fixture change

    public func resetHEAD(to commit: Commit, mode: ResetMode) async throws { await pause() }

    public func revert(_ commit: Commit) async throws {
        // A revert is itself a new commit at the tip — surface one so History updates in the demo.
        await pause()
        insertSyntheticCommit(summary: "Revert \u{201C}\(commit.summary)\u{201D}")
    }

    public func cherryPick(_ commit: Commit) async throws {
        await pause()
        insertSyntheticCommit(summary: commit.summary)
    }

    public func createBranch(named name: String, at commit: Commit) async throws {
        await pause()
        if !branches.contains(where: { $0.name == name }) {
            branches.append(Branch(name: name))
        }
    }

    public func createTag(named name: String, at commit: Commit) async throws { await pause() }   // no tag list in the mock

    // MARK: Helpers

    private func insertSyntheticCommit(summary: String) {
        status.ahead += 1
        commits.insert(makeCommit(summary: summary), at: 0)
    }

    /// Builds a synthetic commit at the tip (parented on the current newest commit). Shared by
    /// `commit`, `pull`, and `insertSyntheticCommit` so the four call sites can't drift apart.
    /// The id doubles as the short SHA; author defaults to the repo's configured author.
    private func makeCommit(idPrefix: String = "mock", summary: String, body: String = "",
                            authorName: String? = nil, authorEmail: String = "you@example.com",
                            authorInitials: String? = nil, files: [FileChange] = []) -> Commit {
        Commit(
            id: "\(idPrefix)\(commits.count)", shortSHA: "\(idPrefix)\(commits.count)",
            summary: summary, body: body,
            authorName: authorName ?? status.author.name, authorEmail: authorEmail,
            authorInitials: authorInitials ?? status.author.initials, date: "Just now", relativeDate: "moments ago",
            refs: [.head], parents: commits.first.map { [$0.shortSHA] } ?? [], files: files
        )
    }

    private func setStaged(_ paths: [String], to staged: Bool) {
        let set = Set(paths)
        status.files = status.files.map { f in
            guard set.contains(f.path) else { return f }
            return FileChange(id: f.id, path: f.path, status: f.status,
                              isStaged: staged, additions: f.additions, deletions: f.deletions)
        }
    }
}
