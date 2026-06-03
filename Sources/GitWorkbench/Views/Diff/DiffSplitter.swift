import Foundation

/// One row of a split diff: a left (old) cell and a right (new) cell, either of which
/// may be `nil` (a missing counterpart). For context lines both sides hold the same line.
struct SplitRow: Identifiable {
    /// Derived from the row's line UUID(s) so it is unique across the WHOLE file. A per-hunk index
    /// would collide between hunks and make a `LazyVStack` render the colliding rows blank.
    let id: UUID
    var left: DiffLine?
    var right: DiffLine?
}

/// Derives split rows from a hunk's unified lines. Port of `splitRows` in reference/src/diff.jsx.
enum DiffSplitter {
    static func rows(_ lines: [DiffLine]) -> [SplitRow] {
        var rows: [SplitRow] = []
        var dels: [DiffLine] = []
        var adds: [DiffLine] = []

        func flush() {
            let count = max(dels.count, adds.count)
            for i in 0..<count {
                let left = i < dels.count ? dels[i] : nil
                let right = i < adds.count ? adds[i] : nil
                rows.append(SplitRow(id: (left ?? right)?.id ?? UUID(), left: left, right: right))
            }
            dels.removeAll(keepingCapacity: true)
            adds.removeAll(keepingCapacity: true)
        }

        for line in lines {
            switch line.kind {
            case .context:
                flush()
                rows.append(SplitRow(id: line.id, left: line, right: line))
            case .deletion:
                dels.append(line)
            case .addition:
                adds.append(line)
            }
        }
        flush()
        return rows
    }
}
