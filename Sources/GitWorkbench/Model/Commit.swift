import Foundation

public struct Commit: Identifiable, Sendable, Hashable {
    public var id: String           // full SHA
    public var shortSHA: String     // "9f2c1a4"
    public var summary: String      // first line of the message
    public var body: String         // remainder (may be empty)
    public var authorName: String
    public var authorEmail: String
    public var authorInitials: String   // "GA" — for the monogram avatar
    public var date: String         // display string, e.g. "Today, 09:42"
    public var relativeDate: String // "3 hours ago"
    public var refs: [CommitRef]    // HEAD / branch / tag pills shown on the row
    public var parents: [String]    // parent short SHAs
    public var files: [FileChange]  // files changed in this commit

    public init(
        id: String, shortSHA: String, summary: String, body: String = "",
        authorName: String, authorEmail: String, authorInitials: String,
        date: String, relativeDate: String,
        refs: [CommitRef] = [], parents: [String] = [], files: [FileChange] = []
    ) {
        self.id = id; self.shortSHA = shortSHA; self.summary = summary; self.body = body
        self.authorName = authorName; self.authorEmail = authorEmail
        self.authorInitials = authorInitials; self.date = date; self.relativeDate = relativeDate
        self.refs = refs; self.parents = parents; self.files = files
    }
}

public enum CommitRef: Sendable, Hashable {
    case head                 // "HEAD" pill (accent)
    case branch(String)       // branch pill (blue) with branch glyph
    case tag(String)          // tag pill (green) with tag glyph
}
