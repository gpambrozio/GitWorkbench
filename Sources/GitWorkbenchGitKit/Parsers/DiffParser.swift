import Foundation
import GitWorkbench

/// Parses unified `git diff` output into a `FileDiff` using the core `DiffBuilder`.
public enum DiffParser {
    public static func parse(unifiedDiff text: String, file: FileChange) -> FileDiff {
        if text.contains("\nBinary files ") || text.hasPrefix("Binary files ") {
            return FileDiff(file: file, hunks: [], isBinary: true)
        }

        var hunks: [DiffHunk] = []
        var oldStart = 0, newStart = 0
        var rawLines: [String] = []
        var inHunk = false

        func flush() {
            guard inHunk else { return }
            hunks.append(DiffBuilder.hunk(oldStart: oldStart, newStart: newStart, rawLines))
            rawLines = []
            inHunk = false
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("@@") {
                flush()
                (oldStart, newStart) = parseHunkStarts(line)
                inHunk = true
            } else if inHunk {
                // Diff body lines start with '+', '-', or ' '. Skip "\ No newline at end of file".
                if line.hasPrefix("\\") { continue }
                if line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ") {
                    rawLines.append(line)
                } else {
                    // An empty line (trailing-newline split artifact) or a new file header ends the
                    // hunk. Genuine blank context lines arrive as " " (caught above), never "".
                    flush()
                }
            }
        }
        flush()
        return FileDiff(file: file, hunks: hunks, isBinary: false)
    }

    /// Parses `@@ -<oldStart>[,len] +<newStart>[,len] @@ ...` → (oldStart, newStart).
    private static func parseHunkStarts(_ header: String) -> (Int, Int) {
        // Find the "-A,B +C,D" portion between the first "@@" pairs.
        let parts = header.split(separator: " ")
        var oldStart = 0, newStart = 0
        for part in parts {
            if part.hasPrefix("-") {
                oldStart = Int(part.dropFirst().split(separator: ",").first ?? "0") ?? 0
            } else if part.hasPrefix("+") {
                newStart = Int(part.dropFirst().split(separator: ",").first ?? "0") ?? 0
            }
        }
        return (oldStart, newStart)
    }
}
