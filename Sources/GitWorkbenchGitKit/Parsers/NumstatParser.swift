import Foundation

/// Parses `git diff --numstat -z` into per-path (additions, deletions). "-" counts (binary) → 0.
public enum NumstatParser {
    public static func parse(_ output: String) -> [String: (additions: Int, deletions: Int)] {
        var result: [String: (additions: Int, deletions: Int)] = [:]
        for record in output.split(separator: "\u{0}", omittingEmptySubsequences: true) {
            let parts = record.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { continue }
            let add = Int(parts[0]) ?? 0      // "-" → nil → 0
            let del = Int(parts[1]) ?? 0
            result[parts[2]] = (add, del)
        }
        return result
    }
}
