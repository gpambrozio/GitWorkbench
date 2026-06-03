import Foundation

/// A file's diff: a list of hunks, each a list of lines (unified form).
/// The split renderer derives two columns from this (Plan 4).
public struct FileDiff: Sendable, Hashable {
    public var file: FileChange
    public var hunks: [DiffHunk]
    public var isBinary: Bool

    public init(file: FileChange, hunks: [DiffHunk], isBinary: Bool = false) {
        self.file = file
        self.hunks = hunks
        self.isBinary = isBinary
    }
}

public struct DiffHunk: Identifiable, Sendable, Hashable {
    public var id: UUID
    public var header: String           // "@@ -14,8 +14,9 @@"
    public var lines: [DiffLine]

    public init(id: UUID = UUID(), header: String, lines: [DiffLine]) {
        self.id = id
        self.header = header
        self.lines = lines
    }
}

public struct DiffLine: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case context, addition, deletion }

    public var id: UUID
    public var kind: Kind
    public var oldNumber: Int?          // line no. in old file (nil for additions)
    public var newNumber: Int?          // line no. in new file (nil for deletions)
    public var text: String             // raw content WITHOUT the +/-/space prefix

    public init(id: UUID = UUID(), kind: Kind, oldNumber: Int?, newNumber: Int?, text: String) {
        self.id = id
        self.kind = kind
        self.oldNumber = oldNumber
        self.newNumber = newNumber
        self.text = text
    }
}
