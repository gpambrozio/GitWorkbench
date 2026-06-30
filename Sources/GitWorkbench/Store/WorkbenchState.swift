import Foundation

/// The value snapshot the whole view tree is a function of.
public struct WorkbenchState: Sendable {
    // active view + diff mode
    public var activeView: WorkspaceView = .changes
    public var diffMode: DiffMode = .split

    // repo status
    public var repo: RepositoryStatus
    public var branches: [Branch] = []
    public var remoteBranches: [RemoteBranch] = []

    // changes view
    public var selectedFileID: FileChange.ID?
    public var commitMessage: String = ""
    public var pendingDiscard: FileChange?     // non-nil → confirm popover up

    // history view
    public var commits: [Commit] = []
    public var selectedCommitID: Commit.ID?
    public var selectedCommitFileID: FileChange.ID?
    public var pendingRefCreation: PendingRefCreation?   // non-nil → name-input popover up
    public var pendingHardReset: Commit?                 // non-nil → confirm hard-reset popover up
    /// Branch whose history is shown (nil = current HEAD). Set by clicking a branch in the rail.
    public var historyBranch: String?
    /// True while a branch's history is being fetched (shows a spinner in the History list).
    public var isLoadingHistory: Bool = false

    // stash view
    public var stashes: [Stash] = []
    public var selectedStashID: Stash.ID?
    public var selectedStashFileID: FileChange.ID?

    // diff cache for the currently shown file
    public var currentDiff: FileDiff?

    // transient
    public var isBusy: Bool = false
    public var toast: Toast?

    public init(repo: RepositoryStatus) { self.repo = repo }

    // derived
    public var staged: [FileChange] { repo.files.filter(\.isStaged) }
    public var unstaged: [FileChange] { repo.files.filter { !$0.isStaged } }
    public var canCommit: Bool {
        !staged.isEmpty &&
        !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// True when History is browsing a branch other than the checked-out one. "Reset HEAD" moves
    /// the *checked-out* branch, not the one whose log is shown, so the UI disables it here to avoid
    /// silently moving/losing work on a different branch than the user is looking at. (Check Out /
    /// Revert / Cherry-Pick act non-destructively on the picked commit SHA and stay enabled.)
    public var isBrowsingOtherBranch: Bool {
        guard let historyBranch else { return false }
        return historyBranch != repo.currentBranch
    }
}

/// A pending "Create New Branch/Tag from <commit>" request, holding the typed name until confirmed.
public struct PendingRefCreation: Sendable, Identifiable {
    public enum Kind: Sendable { case branch, tag }
    public let id = UUID()
    public var kind: Kind
    public var commit: Commit
    public var name: String = ""

    public init(kind: Kind, commit: Commit, name: String = "") {
        self.kind = kind
        self.commit = commit
        self.name = name
    }
}
