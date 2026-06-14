import Foundation

/// In-memory fixture data mirroring reference/src/gitdata.js (repo "aurora-cli").
/// Metadata only — diff hunks are added in the diff-renderer plan.
public enum Fixtures {
    public static let author = Author(name: "Gustavo", initials: "GA")

    // MARK: Working-tree files (7)
    public static let files: [FileChange] = [
        FileChange(path: "src/commands/sync.ts", status: .modified, isStaged: true, additions: 24, deletions: 6),
        FileChange(path: "src/index.ts", status: .modified, isStaged: true, additions: 8, deletions: 2),
        FileChange(path: "src/utils/logger.ts", status: .added, isStaged: true, additions: 31, deletions: 0),
        FileChange(path: "package.json", status: .modified, isStaged: false, additions: 3, deletions: 1),
        FileChange(path: "README.md", status: .modified, isStaged: false, additions: 5, deletions: 0),
        FileChange(path: "src/legacy/poller.ts", status: .deleted, isStaged: false, additions: 0, deletions: 18),
        FileChange(path: ".env.example", status: .untracked, isStaged: false, additions: 4, deletions: 0),
    ]

    public static let repositoryStatus = RepositoryStatus(
        repositoryName: "aurora-cli",
        currentBranch: "feat/auto-sync",
        upstream: "origin/feat/auto-sync",
        ahead: 2, behind: 1,
        files: files, author: author
    )

    // MARK: Commit history (6, newest first)
    public static let commits: [Commit] = [
        Commit(
            id: "9f2c1a4e7b3", shortSHA: "9f2c1a4",
            summary: "Add structured Logger with level colors",
            body: "Replaces scattered console.log calls with a scoped Logger that writes\nleveled, colorized output to stderr. Wires it through the sync command.",
            authorName: "Gustavo", authorEmail: "gustavo@aurora.dev", authorInitials: "GA",
            date: "Today, 09:42", relativeDate: "3 hours ago",
            refs: [.head, .branch("feat/auto-sync")], parents: ["3b8e7d2"],
            files: [
                FileChange(path: "src/utils/logger.ts", status: .added, additions: 31, deletions: 0),
                FileChange(path: "src/commands/sync.ts", status: .modified, additions: 4, deletions: 1),
            ]
        ),
        Commit(
            id: "3b8e7d2f1a9", shortSHA: "3b8e7d2",
            summary: "Switch watcher to fs.watch, drop poller",
            body: "The legacy interval poller is replaced by an fs.watch-based watcher\nfor lower latency and CPU. Removes src/legacy/poller.ts.",
            authorName: "Gustavo", authorEmail: "gustavo@aurora.dev", authorInitials: "GA",
            date: "Yesterday, 18:20", relativeDate: "1 day ago",
            refs: [], parents: ["a17f9c0"],
            files: [
                FileChange(path: "src/commands/watch.ts", status: .added, additions: 22, deletions: 0),
                FileChange(path: "src/legacy/poller.ts", status: .deleted, additions: 0, deletions: 9),
            ]
        ),
        Commit(
            id: "a17f9c0b5e2", shortSHA: "a17f9c0",
            summary: "Bump CLI to 0.5.0-rc.1",
            body: "Pre-release cut for the auto-sync feature branch.",
            authorName: "Mira Patel", authorEmail: "mira@aurora.dev", authorInitials: "MP",
            date: "Mon, 14:05", relativeDate: "3 days ago",
            refs: [.tag("v0.5.0-rc.1")], parents: ["e4d5b61"],
            files: [FileChange(path: "package.json", status: .modified, additions: 1, deletions: 1)]
        ),
        Commit(
            id: "e4d5b61c8d4", shortSHA: "e4d5b61",
            summary: "Format `status` command output as a table",
            body: "Aligns the working-tree status output into columns with status glyphs.",
            authorName: "Mira Patel", authorEmail: "mira@aurora.dev", authorInitials: "MP",
            date: "Mon, 11:32", relativeDate: "3 days ago",
            refs: [], parents: ["77ac3f9"],
            files: [FileChange(path: "src/commands/status.ts", status: .modified, additions: 14, deletions: 6)]
        ),
        Commit(
            id: "77ac3f9d2b6", shortSHA: "77ac3f9",
            summary: "Scaffold sync retry loop",
            body: "First pass at the push retry loop (fixed delay; backoff comes later).",
            authorName: "Gustavo", authorEmail: "gustavo@aurora.dev", authorInitials: "GA",
            date: "Sun, 22:14", relativeDate: "4 days ago",
            refs: [], parents: ["1c0aa28"],
            files: [FileChange(path: "src/commands/sync.ts", status: .added, additions: 18, deletions: 0)]
        ),
        Commit(
            id: "1c0aa28f0c1", shortSHA: "1c0aa28",
            summary: "chore: project scaffolding",
            body: "Initial TypeScript + tsup setup.",
            authorName: "Mira Patel", authorEmail: "mira@aurora.dev", authorInitials: "MP",
            date: "Sat, 10:00", relativeDate: "5 days ago",
            refs: [.branch("main")], parents: [],
            files: [FileChange(path: "package.json", status: .added, additions: 12, deletions: 0)]
        ),
    ]

    // MARK: Stashes (2)
    public static let stashes: [Stash] = [
        Stash(
            id: "stash0", ref: "stash@{0}", message: "WIP: tune retry delays",
            branch: "feat/auto-sync", date: "Today, 12:05", relativeDate: "40 minutes ago",
            files: [FileChange(path: "src/commands/sync.ts", status: .modified, additions: 3, deletions: 2)]
        ),
        Stash(
            id: "stash1", ref: "stash@{1}", message: "experiment: parallel push to mirrors",
            branch: "feat/auto-sync", date: "Sun, 19:48", relativeDate: "2 days ago",
            files: [
                FileChange(path: "src/commands/sync.ts", status: .modified, additions: 6, deletions: 1),
                FileChange(path: "src/config.ts", status: .modified, additions: 2, deletions: 0),
            ]
        ),
    ]

    // MARK: Branches (4)
    public static let branches: [Branch] = [
        Branch(name: "main", isCurrent: false, upstream: "origin/main"),
        Branch(name: "develop", isCurrent: false, upstream: "origin/develop"),
        Branch(name: "feat/auto-sync", isCurrent: true, upstream: "origin/feat/auto-sync"),
        Branch(name: "fix/log-levels", isCurrent: false, upstream: nil),
    ]

    // MARK: Remote branches (alphabetical, like `git for-each-ref`). `origin/feat/auto-sync` is
    // the current branch's upstream (rendered in bold); `origin/release/1.0` has no local branch.
    public static let remoteBranches: [RemoteBranch] = [
        RemoteBranch(remote: "origin", name: "develop"),
        RemoteBranch(remote: "origin", name: "feat/auto-sync"),
        RemoteBranch(remote: "origin", name: "main"),
        RemoteBranch(remote: "origin", name: "release/1.0"),
    ]

    /// A fully-populated initial state for previews and the (later) store/demo.
    public static var initialState: WorkbenchState {
        var s = WorkbenchState(repo: repositoryStatus)
        s.branches = branches
        s.remoteBranches = remoteBranches
        s.commits = commits
        s.stashes = stashes
        return s
    }
}
