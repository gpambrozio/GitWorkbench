import Foundation

/// A small, stable snapshot of the repository's state, handed to a host through the
/// `onRepositorySummaryChange(_:)` view modifier so it can drive its own chrome — a menu-bar item,
/// dock badge, window title, sidebar badge — without running `git` again or reading the store directly.
///
/// Every field is a pure function of `WorkbenchState`; constructing one does no git work. It is
/// `Hashable` (hence `Equatable`), which lets the modifier dedupe: the host's closure fires once with
/// the current value, then only when a *distinct* summary appears.
public struct RepositorySummary: Sendable, Hashable {
    /// Working-tree repository name (`RepositoryStatus.repositoryName`).
    public var repositoryName: String
    /// The checked-out branch (`RepositoryStatus.currentBranch`).
    public var currentBranch: String

    /// Total changed files in the working tree (staged + unstaged).
    public var changedFileCount: Int
    /// Changed files that are staged.
    public var stagedCount: Int
    /// Changed files that are not staged.
    public var unstagedCount: Int
    /// Any changed file is in a merge-conflict state.
    public var hasConflicts: Bool

    /// Added lines summed across all changed files.
    public var additions: Int
    /// Deleted lines summed across all changed files.
    public var deletions: Int

    /// Commits the local branch is ahead of its upstream (to push).
    public var ahead: Int
    /// Commits the local branch is behind its upstream (to pull).
    public var behind: Int
    /// `ahead > 0` — there is something to push.
    public var needsPush: Bool
    /// `behind > 0` — there is something to pull.
    public var needsPull: Bool
    /// The current branch tracks a remote upstream.
    public var hasUpstream: Bool

    /// Nothing to show: no changed files and not ahead or behind the upstream.
    public var isClean: Bool
    /// A pull/push/fetch is currently in flight.
    public var isBusy: Bool

    /// Memberwise initializer (kept accessible for hosts and tests that build a summary directly).
    public init(
        repositoryName: String,
        currentBranch: String,
        changedFileCount: Int,
        stagedCount: Int,
        unstagedCount: Int,
        hasConflicts: Bool,
        additions: Int,
        deletions: Int,
        ahead: Int,
        behind: Int,
        needsPush: Bool,
        needsPull: Bool,
        hasUpstream: Bool,
        isClean: Bool,
        isBusy: Bool
    ) {
        self.repositoryName = repositoryName
        self.currentBranch = currentBranch
        self.changedFileCount = changedFileCount
        self.stagedCount = stagedCount
        self.unstagedCount = unstagedCount
        self.hasConflicts = hasConflicts
        self.additions = additions
        self.deletions = deletions
        self.ahead = ahead
        self.behind = behind
        self.needsPush = needsPush
        self.needsPull = needsPull
        self.hasUpstream = hasUpstream
        self.isClean = isClean
        self.isBusy = isBusy
    }

    /// Derives the summary from the current workbench state. All counts and flags come straight from
    /// `state.repo` (and `state.isBusy`); the single place the derivation lives.
    init(state: WorkbenchState) {
        let repo = state.repo
        let staged = repo.files.lazy.filter(\.isStaged).count
        self.init(
            repositoryName: repo.repositoryName,
            currentBranch: repo.currentBranch,
            changedFileCount: repo.files.count,
            stagedCount: staged,
            unstagedCount: repo.files.count - staged,
            hasConflicts: repo.files.contains { $0.status == .conflicted },
            additions: repo.files.reduce(0) { $0 + $1.additions },
            deletions: repo.files.reduce(0) { $0 + $1.deletions },
            ahead: repo.ahead,
            behind: repo.behind,
            needsPush: repo.ahead > 0,
            needsPull: repo.behind > 0,
            hasUpstream: repo.upstream != nil,
            isClean: repo.files.isEmpty && repo.ahead == 0 && repo.behind == 0,
            isBusy: state.isBusy
        )
    }
}
