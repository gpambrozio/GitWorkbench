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

    /// Derives the summary from the current workbench state. All counts and flags come straight from
    /// `state.repo` (and `state.isBusy`); the single place the derivation lives. The per-file fields are
    /// gathered in one pass over `repo.files`.
    init(state: WorkbenchState) {
        let repo = state.repo
        var staged = 0, additions = 0, deletions = 0, hasConflicts = false
        for file in repo.files {
            if file.isStaged { staged += 1 }
            additions += file.additions
            deletions += file.deletions
            if file.status == .conflicted { hasConflicts = true }
        }
        self.init(
            repositoryName: repo.repositoryName,
            currentBranch: repo.currentBranch,
            stagedCount: staged,
            unstagedCount: repo.files.count - staged,
            hasConflicts: hasConflicts,
            additions: additions,
            deletions: deletions,
            ahead: repo.ahead,
            behind: repo.behind,
            hasUpstream: repo.upstream != nil,
            isBusy: state.isBusy
        )
    }
}
