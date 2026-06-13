import Foundation
import GitWorkbench

/// Parses `git for-each-ref --format='%(refname:short)\u{1f}%(refname:lstrip=3)' refs/remotes`
/// (one ref per line). `lstrip=3` drops `refs/remotes/<remote>/`, leaving the branch name with its
/// remote prefix removed (and intact even when the branch name itself contains slashes). The
/// `<remote>/HEAD` symbolic pointer is skipped.
///
/// Caveat: `lstrip=3` strips exactly three leading components (`refs`, `remotes`, `<remote>`), so it
/// assumes the remote name is a single component. A remote whose own name contains a `/` (e.g.
/// `org/fork`) would leave the remainder in the branch field and mis-split here — vanishingly rare,
/// as remote names don't normally contain slashes.
public enum RemoteRefParser {
    public static func parse(_ output: String) -> [RemoteBranch] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> RemoteBranch? in
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2 else { return nil }
            let short = fields[0], name = fields[1]   // "origin/feat/auto-sync", "feat/auto-sync"
            guard !name.isEmpty, name != "HEAD" else { return nil }   // drop the remote's HEAD pointer
            let suffix = "/" + name
            guard short.hasSuffix(suffix), short.count > suffix.count else { return nil }
            return RemoteBranch(remote: String(short.dropLast(suffix.count)), name: name)
        }
    }
}
