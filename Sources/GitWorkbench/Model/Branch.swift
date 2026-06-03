import Foundation

public struct Branch: Identifiable, Sendable, Hashable {
    public var id: String          // branch name
    public var name: String        // "feat/auto-sync"
    public var isCurrent: Bool
    public var upstream: String?   // "origin/feat/auto-sync"

    public init(name: String, isCurrent: Bool = false, upstream: String? = nil) {
        self.id = name; self.name = name; self.isCurrent = isCurrent; self.upstream = upstream
    }
}
