import Foundation

/// One node in the branch rail's tree. Branch names are split on "/" so that branches sharing a
/// prefix (e.g. `feat/auto-sync`, `feat/login`) nest under a common `feat` folder. A git ref can
/// never be both a branch and a folder prefix, so every node is unambiguously a `leaf` or a
/// `folder` — there is no "branch that also has children" case to reconcile.
struct BranchTreeNode<Leaf>: Identifiable {
    /// Full slash path from the tree root. Unique within the tree, so it doubles as the SwiftUI
    /// `ForEach` id and the base for a folder's collapse-state key — e.g. "feat" or "feat/auto-sync".
    let id: String
    /// Last path component, shown in the row — e.g. "feat" or "auto-sync".
    let name: String
    let kind: Kind

    enum Kind {
        case leaf(Leaf)
        case folder([BranchTreeNode<Leaf>])
    }
}

/// Builds a `/`-delimited tree from a flat branch list. Siblings at every level are sorted
/// case-insensitively by name, interleaving leaf branches and folders into one merged list (issue
/// #7's follow-up). The incoming order is ignored except as a stable tie-breaker.
///
/// `pinnedToTop`, when it matches a top-level node's `id` (i.e. a non-nested branch like the
/// repository's default branch), floats that node ahead of its sorted siblings at the root.
func makeBranchTree<Leaf>(_ items: [Leaf],
                          pinnedToTop: String? = nil,
                          path: (Leaf) -> String) -> [BranchTreeNode<Leaf>] {
    let rows = items.map { item -> BranchRow<Leaf> in
        // `split` drops empty segments, so "a//b" and "a/" collapse cleanly; an empty name keeps a
        // single empty component rather than vanishing.
        let components = path(item).split(separator: "/").map(String.init)
        return BranchRow(components: components.isEmpty ? [path(item)] : components, leaf: item)
    }
    var roots = buildBranchLevel(rows, prefix: "")
    if let pinnedToTop, let idx = roots.firstIndex(where: { $0.id == pinnedToTop }), idx != 0 {
        roots.insert(roots.remove(at: idx), at: 0)
    }
    return roots
}

/// Picks the repository's default branch from a flat list of branch names by a known-name heuristic:
/// the first entry of `priority` that exists in `names` (case-insensitive), returned with its actual
/// casing so callers can match it against a tree node's id. `nil` when none are present.
func defaultBranchName(among names: [String],
                       priority: [String] = ["main", "master", "develop"]) -> String? {
    for candidate in priority {
        if let match = names.first(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
            return match
        }
    }
    return nil
}

/// The collapse key of every folder in `nodes`, depth-first, each prefixed with `keyPrefix` to match
/// `BranchTreeRows`' keying (e.g. "L:" or "R:origin:"). Leaves have no key. Used to build the
/// "everything collapsed" default before re-expanding the path to the current branch.
func folderKeys<Leaf>(_ nodes: [BranchTreeNode<Leaf>], keyPrefix: String) -> [String] {
    var keys: [String] = []
    for node in nodes {
        if case .folder(let children) = node.kind {
            keys.append(keyPrefix + node.id)
            keys.append(contentsOf: folderKeys(children, keyPrefix: keyPrefix))
        }
    }
    return keys
}

/// The collapse keys of the folders that contain `branchName` — its proper slash-prefixes — so the
/// path down to that branch can be left expanded. `prefix/sub/leaf` -> ["<kp>prefix", "<kp>prefix/sub"].
/// A top-level branch (no slash) has no ancestor folders, so this is empty.
func ancestorFolderKeys(of branchName: String, keyPrefix: String) -> [String] {
    let parts = branchName.split(separator: "/").map(String.init)
    guard parts.count > 1 else { return [] }
    var keys: [String] = []
    var path = ""
    for part in parts.dropLast() {
        path = path.isEmpty ? part : "\(path)/\(part)"
        keys.append(keyPrefix + path)
    }
    return keys
}

/// Folds a new set of visible folders into the user's existing collapse state when the branch list
/// changes. Folders that appeared since `knownFolders` default to collapsed; folders the user has
/// already toggled keep their state; folders that vanished are dropped. So manual expand/collapse
/// survives an external refresh, while brand-new folders still start collapsed.
func reconcileCollapsed(previous: Set<String>, knownFolders: Set<String>, allFolders: Set<String>) -> Set<String> {
    previous.union(allFolders.subtracting(knownFolders)).intersection(allFolders)
}

private struct BranchRow<Leaf> {
    let components: [String]
    let leaf: Leaf
}

private func buildBranchLevel<Leaf>(_ rows: [BranchRow<Leaf>], prefix: String) -> [BranchTreeNode<Leaf>] {
    var order: [String] = []
    var groups: [String: [BranchRow<Leaf>]] = [:]
    for row in rows {
        guard let head = row.components.first else {
            // Only reachable if a ref were both a branch and a folder prefix (e.g. `feat` and
            // `feat/x`), which git's ref store forbids. Fail loud in debug rather than silently
            // dropping the branch; release builds skip the row instead of crashing.
            assertionFailure("Branch ref produced an empty path segment — a ref cannot be both a branch and a folder prefix")
            continue
        }
        if groups[head] == nil {
            order.append(head)
            groups[head] = [row]
        } else {
            groups[head]?.append(row)
        }
    }

    var nodes: [BranchTreeNode<Leaf>] = []
    for head in order {
        let group = groups[head]!
        let id = prefix.isEmpty ? head : "\(prefix)/\(head)"
        if group.count == 1, let only = group.first, only.components.count == 1 {
            nodes.append(BranchTreeNode(id: id, name: head, kind: .leaf(only.leaf)))
        } else {
            let children = buildBranchLevel(group.map { BranchRow(components: Array($0.components.dropFirst()), leaf: $0.leaf) },
                                            prefix: id)
            nodes.append(BranchTreeNode(id: id, name: head, kind: .folder(children)))
        }
    }
    // Sort branches and folders together, case-insensitively. `caseInsensitiveCompare` (not the
    // localized variant) keeps ordering deterministic across locales; `sort` is stable, so equal
    // keys hold their insertion order. Sibling names are unique per level (dictionary keys), so the
    // only true ties are pure-case variants like "Feat"/"feat".
    nodes.sort { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending }
    return nodes
}
