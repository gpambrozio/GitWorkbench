import Foundation

public struct Branch: Identifiable, Sendable, Hashable {
    public var id: String          // branch name
    public var name: String        // "feat/auto-sync"
    public var isCurrent: Bool
    public var upstream: String?   // "origin/feat/auto-sync"
    public var ahead: Int          // commits ahead of `upstream` (to push); 0 when in sync or untracked
    public var behind: Int         // commits behind `upstream` (to pull); 0 when in sync or untracked

    public init(name: String, isCurrent: Bool = false, upstream: String? = nil,
                ahead: Int = 0, behind: Int = 0) {
        self.id = name; self.name = name; self.isCurrent = isCurrent; self.upstream = upstream
        self.ahead = ahead; self.behind = behind
    }
}
