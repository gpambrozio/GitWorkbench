import Foundation
import GitWorkbench

/// Parses `git for-each-ref --format='%(refname:short)\u{1f}%(upstream:short)\u{1f}%(HEAD)\u{1f}%(upstream:track)'`
/// (one ref per line).
public enum RefParser {
    public static func parse(_ output: String) -> [Branch] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> Branch? in
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard let name = fields.first, !name.isEmpty else { return nil }
            let upstream = fields.count > 1 && !fields[1].isEmpty ? fields[1] : nil
            let isCurrent = fields.count > 2 && fields[2] == "*"
            let track = parseTrack(fields.count > 3 ? fields[3] : "")
            return Branch(name: name, isCurrent: isCurrent, upstream: upstream,
                          ahead: track.ahead, behind: track.behind)
        }
    }

    /// Parses git's `%(upstream:track)` field into ahead/behind commit counts. git emits
    /// `[ahead 2, behind 1]`, `[ahead 3]`, `[behind 4]`, `[gone]` (upstream deleted), or an empty
    /// string (in sync, or no upstream). Anything without an explicit count — including `[gone]` and
    /// the empty string — yields `(0, 0)`.
    static func parseTrack(_ field: String) -> (ahead: Int, behind: Int) {
        let inner = field.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        guard !inner.isEmpty, inner != "gone" else { return (0, 0) }
        var ahead = 0, behind = 0
        for segment in inner.split(separator: ",") {
            let tokens = segment.split(separator: " ", omittingEmptySubsequences: true)
            guard tokens.count == 2, let count = Int(tokens[1]) else { continue }
            switch tokens[0] {
            case "ahead":  ahead = count
            case "behind": behind = count
            default:       break
            }
        }
        return (ahead, behind)
    }
}
