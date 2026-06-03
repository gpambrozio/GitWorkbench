import Foundation

/// Builds `DiffHunk`/`FileDiff` values from a compact patch representation.
/// Port of `hunk()` in reference/src/gitdata.js.
public enum DiffBuilder {
    /// Each raw line is prefixed with `+` (addition), `-` (deletion), or a space (context).
    /// The prefix is stripped into `text`; line numbers advance per the prototype's rules.
    public static func hunk(oldStart: Int, newStart: Int, _ raw: [String]) -> DiffHunk {
        var oldNo = oldStart
        var newNo = newStart
        var lines: [DiffLine] = []
        lines.reserveCapacity(raw.count)

        for line in raw {
            let prefix = line.first
            let text = String(line.dropFirst())
            switch prefix {
            case "+":
                lines.append(DiffLine(kind: .addition, oldNumber: nil, newNumber: newNo, text: text))
                newNo += 1
            case "-":
                lines.append(DiffLine(kind: .deletion, oldNumber: oldNo, newNumber: nil, text: text))
                oldNo += 1
            default: // space or empty → context
                lines.append(DiffLine(kind: .context, oldNumber: oldNo, newNumber: newNo, text: text))
                oldNo += 1
                newNo += 1
            }
        }

        let oldCount = lines.lazy.filter { $0.kind != .addition }.count
        let newCount = lines.lazy.filter { $0.kind != .deletion }.count
        let header = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
        return DiffHunk(header: header, lines: lines)
    }

    /// Convenience to assemble a `FileDiff` from a file and its hunks.
    public static func fileDiff(_ file: FileChange, hunks: [DiffHunk], isBinary: Bool = false) -> FileDiff {
        FileDiff(file: file, hunks: hunks, isBinary: isBinary)
    }
}
