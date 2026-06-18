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

/// Builds a `/`-delimited tree from a flat branch list. Within each level, leaf branches are listed
/// before folders (matching issue #7's design, where `main` sits above the `feat/` group); the
/// incoming order is otherwise preserved, so a provider's alphabetical sort carries through.
func makeBranchTree<Leaf>(_ items: [Leaf], path: (Leaf) -> String) -> [BranchTreeNode<Leaf>] {
    let rows = items.map { item -> BranchRow<Leaf> in
        // `split` drops empty segments, so "a//b" and "a/" collapse cleanly; an empty name keeps a
        // single empty component rather than vanishing.
        let components = path(item).split(separator: "/").map(String.init)
        return BranchRow(components: components.isEmpty ? [path(item)] : components, leaf: item)
    }
    return buildBranchLevel(rows, prefix: "")
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

    var leaves: [BranchTreeNode<Leaf>] = []
    var folders: [BranchTreeNode<Leaf>] = []
    for head in order {
        let group = groups[head]!
        let id = prefix.isEmpty ? head : "\(prefix)/\(head)"
        if group.count == 1, let only = group.first, only.components.count == 1 {
            leaves.append(BranchTreeNode(id: id, name: head, kind: .leaf(only.leaf)))
        } else {
            let children = buildBranchLevel(group.map { BranchRow(components: Array($0.components.dropFirst()), leaf: $0.leaf) },
                                            prefix: id)
            folders.append(BranchTreeNode(id: id, name: head, kind: .folder(children)))
        }
    }
    return leaves + folders
}
