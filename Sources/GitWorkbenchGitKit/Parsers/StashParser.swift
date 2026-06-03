import Foundation
import GitWorkbench

/// Parses `git stash list --format='%gd\u{1f}%s\u{1f}%cr'` (one stash per line). Files are loaded
/// separately by the provider (Plan 10); `branch` is the current branch for display.
public enum StashParser {
    public static func parse(_ output: String, branch: String) -> [Stash] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> Stash? in
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard let ref = fields.first, !ref.isEmpty else { return nil }
            let message = fields.count > 1 ? fields[1] : ""
            let relative = fields.count > 2 ? fields[2] : ""
            return Stash(id: ref, ref: ref, message: message, branch: branch, date: relative, relativeDate: relative, files: [])
        }
    }
}
