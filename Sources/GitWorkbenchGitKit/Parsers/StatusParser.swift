import Foundation
import GitWorkbench

public enum StatusParser {
    public struct Result {
        public var branch: String
        public var upstream: String?
        public var ahead: Int
        public var behind: Int
        public var files: [FileChange]
    }

    public static func parse(porcelain output: String) -> Result {
        var branch = "", upstream: String? = nil, ahead = 0, behind = 0
        var files: [FileChange] = []
        let records = output.split(separator: "\u{0}", omittingEmptySubsequences: true).map(String.init)

        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            if record.hasPrefix("# branch.head ") {
                branch = String(record.dropFirst("# branch.head ".count))
            } else if record.hasPrefix("# branch.upstream ") {
                upstream = String(record.dropFirst("# branch.upstream ".count))
            } else if record.hasPrefix("# branch.ab ") {
                let ab = record.dropFirst("# branch.ab ".count).split(separator: " ")
                for token in ab {
                    if token.hasPrefix("+") { ahead = Int(token.dropFirst()) ?? 0 }
                    else if token.hasPrefix("-") { behind = Int(token.dropFirst()) ?? 0 }
                }
            } else if record.hasPrefix("1 ") {
                files.append(contentsOf: ordinary(record))
            } else if record.hasPrefix("2 ") {
                files.append(contentsOf: ordinary(record))   // rename: treat by its new path
                index += 1                                    // skip the original-path record
            } else if record.hasPrefix("? ") {
                files.append(FileChange(path: String(record.dropFirst(2)), status: .untracked, isStaged: false))
            } else if record.hasPrefix("u ") {
                // u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path> — path is field 10+.
                let fields = record.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                if fields.count > 10 {
                    files.append(FileChange(path: fields[10...].joined(separator: " "),
                                            status: .conflicted, isStaged: false))
                }
            }
        }
        return Result(branch: branch, upstream: upstream, ahead: ahead, behind: behind, files: files)
    }

    /// A `1`/`2` entry: `<type> <XY> <sub> <mH> <mI> <mW> <hH> <hI> [<score>] <path>`.
    private static func ordinary(_ record: String) -> [FileChange] {
        let fields = record.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 9 else { return [] }
        let xy = Array(fields[1])
        guard xy.count == 2 else { return [] }
        // path is everything after the 8th field (type=0..path). For `1`, fields 0..7 are metadata, 8+ path.
        // For `2`, an extra score field shifts path to 9+. Detect by type.
        let pathStartField = record.hasPrefix("2 ") ? 9 : 8
        guard fields.count > pathStartField else { return [] }
        let path = fields[pathStartField...].joined(separator: " ")

        var out: [FileChange] = []
        if xy[0] != "." {
            out.append(FileChange(id: out.isEmpty && xy[1] == "." ? path : "\(path):staged",
                                  path: path, status: status(for: xy[0]), isStaged: true))
        }
        if xy[1] != "." {
            out.append(FileChange(id: xy[0] == "." ? path : "\(path):unstaged",
                                  path: path, status: status(for: xy[1]), isStaged: false))
        }
        return out
    }

    private static func status(for code: Character) -> FileStatus {
        switch code {
        case "A": return .added
        case "D": return .deleted
        case "R", "C": return .renamed
        case "U": return .conflicted
        default: return .modified
        }
    }
}
