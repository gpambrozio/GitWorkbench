import Foundation

/// A small, stable snapshot of the repository's state, handed to a host through the
/// `onRepositorySummaryChange(_:)` view modifier so it can drive its own chrome — a menu-bar item,
/// dock badge, window title, sidebar badge — without running `git` again or reading the store directly.
///
/// Every field is a pure function of `WorkbenchState`; constructing one does no git work. It is
/// `Hashable` (hence `Equatable`), which lets the modifier dedupe: the host's closure fires once with
/// the current value, then only when a *distinct* summary appears.
///
/// Only the independent primitives are stored; the convenience flags (`changedFileCount`, `needsPush`,
/// `needsPull`, `isClean`) are **computed** from them, so a summary can never be internally
/// inconsistent and `Hashable` hashes only the underlying state.
public struct RepositorySummary: Sendable, Hashable {
    /// Working-tree repository name (`RepositoryStatus.repositoryName`).
    public var repositoryName: String
    /// The checked-out branch (`RepositoryStatus.currentBranch`).
    public var currentBranch: String

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
    /// The current branch tracks a remote upstream.
    public var hasUpstream: Bool

    /// A pull/push/fetch is currently in flight.
    public var isBusy: Bool

    /// Total changed files in the working tree (staged + unstaged).
    public var changedFileCount: Int { stagedCount + unstagedCount }
    /// `ahead > 0` — there is something to push.
    public var needsPush: Bool { ahead > 0 }
    /// `behind > 0` — there is something to pull.
    public var needsPull: Bool { behind > 0 }
    /// Nothing to show: no changed files and not ahead or behind the upstream.
    public var isClean: Bool { changedFileCount == 0 && ahead == 0 && behind == 0 }

    /// Memberwise initializer over the stored primitives (kept accessible for hosts and tests that build
    /// a summary directly). The convenience flags are derived, so they can't be passed inconsistently.
    public init(
        repositoryName: String,
        currentBranch: String,
        stagedCount: Int,
        unstagedCount: Int,
        hasConflicts: Bool,
        additions: Int,
        deletions: Int,
        ahead: Int,
        behind: Int,
        hasUpstream: Bool,
        isBusy: Bool
    ) {
        self.repositoryName = repositoryName
        self.currentBranch = currentBranch
        self.stagedCount = stagedCount
        self.unstagedCount = unstagedCount
        self.hasConflicts = hasConflicts
        self.additions = additions
        self.deletions = deletions
        self.ahead = ahead
        self.behind = behind
        self.hasUpstream = hasUpstream
        self.isBusy = isBusy
    }

    /// Derives the summary from a ``RepositoryStatus`` (plus the in-flight `isBusy` flag). The single
    /// place the per-file derivation lives — counts and churn are gathered in one pass over
    /// `status.files`. Public so a host that keeps its own `RepositoryStatus` (rather than reading
    /// ``GitWorkbenchStore/summary``) can derive an identical summary.
    public init(_ status: RepositoryStatus, isBusy: Bool = false) {
        var staged = 0, additions = 0, deletions = 0, hasConflicts = false
        for file in status.files {
            if file.isStaged { staged += 1 }
            additions += file.additions
            deletions += file.deletions
            if file.status == .conflicted { hasConflicts = true }
        }
        self.init(
            repositoryName: status.repositoryName,
            currentBranch: status.currentBranch,
            stagedCount: staged,
            unstagedCount: status.files.count - staged,
            hasConflicts: hasConflicts,
            additions: additions,
            deletions: deletions,
            ahead: status.ahead,
            behind: status.behind,
            hasUpstream: status.upstream != nil,
            isBusy: isBusy
        )
    }

    /// Derives the summary from the current workbench state. Convenience over ``init(_:isBusy:)``.
    init(state: WorkbenchState) {
        self.init(state.repo, isBusy: state.isBusy)
    }
}
