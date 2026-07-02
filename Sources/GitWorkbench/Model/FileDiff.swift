import Foundation

/// A file's diff: a list of hunks, each a list of lines (unified form).
/// The split renderer derives two columns from this (Plan 4).
public struct FileDiff: Sendable, Hashable {
    public var file: FileChange
    public var hunks: [DiffHunk]
    public var isBinary: Bool
    /// Renderable bytes for a binary file the viewer can display (images, PDFs). When set, the diff
    /// pane shows the rich image/PDF comparison instead of the "Binary file" placeholder. `nil` for a
    /// text diff or a binary the built-in viewers don't understand. See ``BinaryContent``.
    public var binaryContent: BinaryContent?

    public init(file: FileChange, hunks: [DiffHunk], isBinary: Bool = false, binaryContent: BinaryContent? = nil) {
        self.file = file
        self.hunks = hunks
        // Carrying renderable binary content implies the file is binary — keep the flag consistent so
        // existing `isBinary` checks still hold whether or not the content could be loaded.
        self.isBinary = isBinary || binaryContent != nil
        self.binaryContent = binaryContent
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
