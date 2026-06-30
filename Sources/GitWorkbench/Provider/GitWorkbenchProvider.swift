import Foundation

/// The full host integration surface: a data source plus an action handler.
public protocol GitWorkbenchProvider: GitWorkbenchDataSource, GitWorkbenchActionHandler {}

/// Reads repository state. All methods run off the main actor; the provider is `Sendable`.
public protocol GitWorkbenchDataSource: Sendable {
    /// Working-tree status: branch, ahead/behind, staged + unstaged files.
    func loadStatus() async throws -> RepositoryStatus
    /// Commit history starting at `ref` (a branch name; nil = current HEAD), newest first.
    /// `before` pages older than that commit (by SHA, so it is branch-independent).
    func loadHistory(of ref: String?, before: Commit.ID?, limit: Int) async throws -> [Commit]
    /// Stash entries (index 0 newest).
    func loadStashes() async throws -> [Stash]
    /// Local branches for the switcher.
    func loadBranches() async throws -> [Branch]
    /// Remote-tracking branches for the switcher (every remote, not just the current upstream).
    func loadRemoteBranches() async throws -> [RemoteBranch]
    /// The diff for one file in a given context (working tree, a commit, or a stash).
    func loadDiff(_ request: DiffRequest) async throws -> FileDiff

    /// An optional stream that emits whenever the repository changes on disk (external
    /// edits, commits, branch switches, stashes). The store subscribes to it on load and
    /// reloads automatically, so a host gets live updates without wiring its own file
    /// watcher. Return `nil` (the default) for providers that can't observe the
    /// filesystem — e.g. the mock; the host can still drive refreshes via `reload()`.
    func repositoryChanges() -> AsyncStream<Void>?
}

extension GitWorkbenchDataSource {
    public func repositoryChanges() -> AsyncStream<Void>? { nil }
}

/// Performs git operations on behalf of the UI.
public protocol GitWorkbenchActionHandler: Sendable {
    func stage(_ files: [FileChange]) async throws
    func unstage(_ files: [FileChange]) async throws
    func discard(_ file: FileChange) async throws
    func commit(message: String, staged: [FileChange]) async throws -> Commit

    func pull() async throws -> SyncResult
    func push() async throws -> SyncResult
    func fetch() async throws -> SyncResult
    func switchBranch(to branch: Branch) async throws
    /// Check out a remote branch locally, creating a local tracking branch for it.
    func checkoutRemoteBranch(_ branch: RemoteBranch) async throws

    func applyStash(_ stash: Stash) async throws
    func popStash(_ stash: Stash) async throws
    func dropStash(_ stash: Stash) async throws

    // History context-menu actions (right-click a commit).
    /// Check out a commit, detaching HEAD at it.
    func checkout(_ commit: Commit) async throws
    /// Move the current branch's HEAD to `commit` (`git reset --soft|--mixed|--hard`).
    func resetHEAD(to commit: Commit, mode: ResetMode) async throws
    /// Create a new commit that undoes `commit` (`git revert`).
    func revert(_ commit: Commit) async throws
    /// Apply `commit` on top of the current branch (`git cherry-pick`).
    func cherryPick(_ commit: Commit) async throws
    /// Create a new branch pointing at `commit` (without switching to it).
    func createBranch(named name: String, at commit: Commit) async throws
    /// Create a new lightweight tag pointing at `commit`.
    func createTag(named name: String, at commit: Commit) async throws
}

/// The `git reset` mode picked from the "Reset HEAD to…" submenu.
public enum ResetMode: String, Sendable, CaseIterable {
    case soft, mixed, hard

    /// Label shown in the "Reset HEAD to…" submenu, describing what each mode keeps or discards.
    public var menuLabel: String {
        switch self {
        case .soft:  "Soft \u{2014} keep all changes staged"
        case .mixed: "Mixed \u{2014} keep changes, unstaged"
        case .hard:  "Hard \u{2014} discard all changes"
        }
    }

    /// True for the irreversible mode (`--hard` throws away uncommitted work); the UI confirms it first.
    public var isDestructive: Bool { self == .hard }
}

/// Identifies which diff to load.
public struct DiffRequest: Sendable {
    public enum Context: Sendable {
        case workingTree(staged: Bool)
        case commit(Commit.ID)
        case stash(Stash.ID)
    }
    public var file: FileChange
    public var context: Context
    public var mode: DiffMode   // a hint; the renderer can re-derive split from unified

    public init(file: FileChange, context: Context, mode: DiffMode) {
        self.file = file
        self.context = context
        self.mode = mode
    }
}

/// The result of a pull/push/fetch.
public struct SyncResult: Sendable {
    public var ahead: Int
    public var behind: Int
    public var message: String   // e.g. "Pushed 2 commits to origin"

    public init(ahead: Int, behind: Int, message: String) {
        self.ahead = ahead
        self.behind = behind
        self.message = message
    }
}
