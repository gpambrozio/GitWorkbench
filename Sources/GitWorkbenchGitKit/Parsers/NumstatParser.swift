import Foundation

/// Parses `git diff --numstat -z` into per-path (additions, deletions). "-" counts (binary) → 0.
public enum NumstatParser {
    public static func parse(_ output: String) -> [String: (additions: Int, deletions: Int)] {
        var result: [String: (additions: Int, deletions: Int)] = [:]
        let records = output.split(separator: "\u{0}", omittingEmptySubsequences: true).map(String.init)
        var index = 0
        while index < records.count {
            // A stat record is "<add>\t<del>\t<path>". For a rename/copy under `-z` the path field is
            // EMPTY and the old + new paths follow as their own NUL-separated records:
            //   "1\t0\t" \0 "old" \0 "new" \0   — key the count by the NEW path (how status identifies it).
            let parts = records[index].split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            index += 1
            guard parts.count == 3 else { continue }   // stray path token (already consumed below); skip
            let add = Int(parts[0]) ?? 0               // "-" (binary) → nil → 0
            let del = Int(parts[1]) ?? 0
            if parts[2].isEmpty {
                guard index + 1 < records.count else { continue }   // truncated; nothing to key by
                result[records[index + 1]] = (add, del)             // records[index] = old, [index+1] = new
                index += 2
            } else {
                result[parts[2]] = (add, del)
            }
        }
        return result
    }
}
