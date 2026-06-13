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
}
