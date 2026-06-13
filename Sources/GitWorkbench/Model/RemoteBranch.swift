import Foundation

/// A remote-tracking branch (e.g. `origin/feat/auto-sync`). `name` has the remote prefix
/// stripped for display; `id` keeps the full ref so it stays unique across remotes.
public struct RemoteBranch: Identifiable, Sendable, Hashable {
    public var id: String      // full ref, e.g. "origin/feat/auto-sync"
    public var remote: String  // "origin"
    public var name: String    // "feat/auto-sync" (remote prefix removed)

    public init(remote: String, name: String) {
        self.remote = remote
        self.name = name
        self.id = "\(remote)/\(name)"
    }
}
