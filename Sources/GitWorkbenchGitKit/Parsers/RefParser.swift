import Foundation
import GitWorkbench

/// Parses `git for-each-ref --format='%(refname:short)\u{1f}%(upstream:short)\u{1f}%(HEAD)'` (one ref per line).
public enum RefParser {
    public static func parse(_ output: String) -> [Branch] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> Branch? in
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard let name = fields.first, !name.isEmpty else { return nil }
            let upstream = fields.count > 1 && !fields[1].isEmpty ? fields[1] : nil
            let isCurrent = fields.count > 2 && fields[2] == "*"
            return Branch(name: name, isCurrent: isCurrent, upstream: upstream)
        }
    }
}
