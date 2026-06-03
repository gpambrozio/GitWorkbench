import Foundation
import GitWorkbench

/// Parses field/record-delimited `git log` output into `[Commit]`.
/// Record fields: H, h, an, ae, aI, cI, P, D, s, b  (sep `\u{1f}`); records sep `\u{1e}`.
public enum LogParser {
    public static func parse(_ output: String) -> [Commit] {
        output.split(separator: "\u{1e}", omittingEmptySubsequences: true).compactMap { rawRecord -> Commit? in
            let fields = rawRecord
                .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
                .split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 10 else { return nil }
            let parents = fields[6].split(separator: " ").map(String.init).filter { !$0.isEmpty }
            return Commit(
                id: fields[0], shortSHA: fields[1], summary: fields[8], body: fields[9],
                authorName: fields[2], authorEmail: fields[3], authorInitials: initials(for: fields[2]),
                date: displayDate(fields[5]), relativeDate: "", refs: refs(from: fields[7]),
                parents: parents, files: []
            )
        }
    }

    /// Parses git's `%D` decoration string into typed refs (HEAD, branches, tags).
    static func refs(from decoration: String) -> [CommitRef] {
        var result: [CommitRef] = []
        for part in decoration.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
            if part == "HEAD" || part.hasPrefix("HEAD -> ") {
                result.append(.head)
                if let arrow = part.range(of: "HEAD -> ") {
                    result.append(.branch(String(part[arrow.upperBound...])))
                }
            } else if part.hasPrefix("tag: ") {
                result.append(.tag(String(part.dropFirst("tag: ".count))))
            } else if !part.contains("/") {       // a local branch (skip remote-tracking like origin/x)
                result.append(.branch(part))
            }
        }
        return result
    }

    static func initials(for name: String) -> String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        if words.isEmpty { return "?" }
        if words.count == 1 { return String(words[0].prefix(1)).uppercased() }
        return (String(words[0].prefix(1)) + String(words[words.count - 1].prefix(1))).uppercased()
    }

    private static func displayDate(_ iso: String) -> String { String(iso.prefix(10)) }  // YYYY-MM-DD
}
