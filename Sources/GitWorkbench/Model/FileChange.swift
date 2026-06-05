import Foundation

/// One changed file in the working tree, a commit, or a stash.
public struct FileChange: Identifiable, Hashable, Sendable {
    public var id: String          // stable key; defaults to the repo-relative path
    public var path: String        // "src/commands/sync.ts"
    public var directory: String   // "src/commands" ("" for a root file)
    public var name: String        // "sync.ts"
    public var status: FileStatus
    public var isStaged: Bool       // only meaningful in working-tree context
    public var additions: Int
    public var deletions: Int

    /// Designated initializer. `directory`/`name` are derived from `path` unless given.
    public init(
        id: String? = nil,
        path: String,
        status: FileStatus,
        isStaged: Bool = false,
        additions: Int = 0,
        deletions: Int = 0
    ) {
        self.id = id ?? path
        self.path = path
        let slash = path.lastIndex(of: "/")
        if let slash {
            self.directory = String(path[..<slash])
            self.name = String(path[path.index(after: slash)...])
        } else {
            self.directory = ""
            self.name = path
        }
        self.status = status
        self.isStaged = isStaged
        self.additions = additions
        self.deletions = deletions
    }

    /// The file's location on disk, resolving the repo-relative `path` against `root` (the repository's
    /// working-tree root, supplied by the host via `WorkbenchConfiguration.repositoryURL`). When `root`
    /// is nil the result is a path-only file URL — useful enough for a host that knows its own root.
    func url(relativeTo root: URL?) -> URL {
        guard let root else { return URL(filePath: path) }
        return root.appending(path: path)
    }
}
