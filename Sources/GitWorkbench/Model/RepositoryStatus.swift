import Foundation

public struct RepositoryStatus: Sendable, Hashable {
    public var repositoryName: String   // "aurora-cli"
    public var currentBranch: String    // "feat/auto-sync"
    public var upstream: String?        // "origin/feat/auto-sync"
    public var ahead: Int               // commits to push
    public var behind: Int              // commits to pull
    public var files: [FileChange]      // all changed files (staged flag set per file)
    public var author: Author           // current user, for the composer avatar

    public init(
        repositoryName: String, currentBranch: String, upstream: String? = nil,
        ahead: Int = 0, behind: Int = 0, files: [FileChange] = [], author: Author
    ) {
        self.repositoryName = repositoryName; self.currentBranch = currentBranch
        self.upstream = upstream; self.ahead = ahead; self.behind = behind
        self.files = files; self.author = author
    }
}

public struct Author: Sendable, Hashable {
    public var name: String
    public var initials: String
    public init(name: String, initials: String) { self.name = name; self.initials = initials }
}
