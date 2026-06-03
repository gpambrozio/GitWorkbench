import Foundation

public struct Stash: Identifiable, Sendable, Hashable {
    public var id: String          // stable key
    public var ref: String         // "stash@{0}"
    public var message: String     // "WIP: tune retry delays"
    public var branch: String      // branch it was created on
    public var date: String        // "Today, 12:05"
    public var relativeDate: String// "40 minutes ago"
    public var files: [FileChange]

    public init(
        id: String, ref: String, message: String, branch: String,
        date: String, relativeDate: String, files: [FileChange] = []
    ) {
        self.id = id; self.ref = ref; self.message = message; self.branch = branch
        self.date = date; self.relativeDate = relativeDate; self.files = files
    }
}
