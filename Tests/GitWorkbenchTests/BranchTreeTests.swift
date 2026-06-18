import XCTest
@testable import GitWorkbench

final class BranchTreeTests: XCTestCase {
    func test_emptyInputMakesEmptyTree() {
        XCTAssertTrue(makeBranchTree([String]()) { $0 }.isEmpty)
    }

    func test_flatLeavesPreserveInputOrder() {
        let tree = makeBranchTree(["main", "develop", "zeta"]) { $0 }
        XCTAssertEqual(tree.map(\.name), ["main", "develop", "zeta"])
        XCTAssertEqual(tree.map(\.id), ["main", "develop", "zeta"])
        XCTAssertTrue(tree.allSatisfy(isLeaf))
    }

    func test_leavesSortBeforeFoldersAndNest() {
        let tree = makeBranchTree(["claude/issue-597", "claude/issue-600", "docs/x", "main"]) { $0 }
        // `main` is a leaf, so it leads despite sorting last alphabetically (issue #7's design).
        XCTAssertEqual(tree.map(\.name), ["main", "claude", "docs"])
        XCTAssertEqual(tree.map(\.id), ["main", "claude", "docs"])
        XCTAssertTrue(isLeaf(tree[0]))

        let claude = children(tree[1])
        XCTAssertEqual(claude.map(\.name), ["issue-597", "issue-600"])
        XCTAssertEqual(claude.map(\.id), ["claude/issue-597", "claude/issue-600"])
        XCTAssertTrue(claude.allSatisfy(isLeaf))
    }

    func test_singleNestedBranchBecomesAFolder() {
        let tree = makeBranchTree(["feat/auto-sync"]) { $0 }
        XCTAssertEqual(tree.map(\.name), ["feat"])
        let kids = children(tree[0])
        XCTAssertEqual(kids.map(\.name), ["auto-sync"])
        XCTAssertEqual(kids.map(\.id), ["feat/auto-sync"])
        XCTAssertEqual(leafValue(kids[0]), "feat/auto-sync")
    }

    func test_deepNestingChainsFolders() {
        let tree = makeBranchTree(["a/b/c"]) { $0 }
        XCTAssertEqual(tree.map(\.name), ["a"])
        let b = children(tree[0])
        XCTAssertEqual(b.map(\.id), ["a/b"])
        let c = children(b[0])
        XCTAssertEqual(c.map(\.id), ["a/b/c"])
        XCTAssertTrue(isLeaf(c[0]))
    }

    func test_leavesSortBeforeFoldersWithinAFolder() {
        // The leaves-before-folders rule must also hold *inside* a folder, not just at the root.
        let tree = makeBranchTree(["a/sub/x", "a/leaf"]) { $0 }
        XCTAssertEqual(tree.map(\.name), ["a"])
        let a = children(tree[0])
        XCTAssertEqual(a.map(\.name), ["leaf", "sub"])  // leaf precedes folder despite trailing input
        XCTAssertTrue(isLeaf(a[0]))
        XCTAssertEqual(leafValue(a[0]), "a/leaf")
        XCTAssertEqual(children(a[1]).map(\.id), ["a/sub/x"])
    }

    func test_extraSlashesCollapse() {
        // git never emits these, but the splitter must not produce empty segments or drop the ref.
        let tree = makeBranchTree(["a//b", "trailing/"]) { $0 }
        XCTAssertEqual(tree.map(\.name), ["trailing", "a"])  // "trailing/" -> single leaf "trailing"
        XCTAssertEqual(children(tree[1]).map(\.id), ["a/b"])
    }

    func test_localBranchFixturesCarryTheBranchValue() {
        let tree = makeBranchTree(Fixtures.branches) { $0.name }
        // provider order is main, develop, feat/auto-sync, fix/log-levels -> leaves then folders.
        XCTAssertEqual(tree.map(\.name), ["main", "develop", "feat", "fix"])
        XCTAssertEqual(leafValue(tree[0])?.name, "main")

        let feat = children(tree[2])
        XCTAssertEqual(feat.map(\.name), ["auto-sync"])
        XCTAssertEqual(leafValue(feat[0])?.name, "feat/auto-sync")
        XCTAssertEqual(leafValue(feat[0])?.isCurrent, true)
        XCTAssertEqual(children(tree[3]).map(\.name), ["log-levels"])
    }

    func test_remoteBranchFixturesKeepFullRefIDs() {
        let origin = Fixtures.remoteBranches.filter { $0.remote == "origin" }
        let tree = makeBranchTree(origin) { $0.name }
        XCTAssertEqual(tree.map(\.name), ["develop", "main", "feat", "release"])

        let feat = children(tree[2])
        XCTAssertEqual(feat.map(\.name), ["auto-sync"])
        XCTAssertEqual(leafValue(feat[0])?.id, "origin/feat/auto-sync")

        let release = children(tree[3])
        XCTAssertEqual(release.map(\.name), ["1.0"])
        XCTAssertEqual(leafValue(release[0])?.id, "origin/release/1.0")
    }
}

// MARK: - Tree-shape helpers

private func isLeaf<Leaf>(_ node: BranchTreeNode<Leaf>) -> Bool {
    if case .leaf = node.kind { return true }
    return false
}

private func leafValue<Leaf>(_ node: BranchTreeNode<Leaf>) -> Leaf? {
    if case .leaf(let value) = node.kind { return value }
    return nil
}

private func children<Leaf>(_ node: BranchTreeNode<Leaf>) -> [BranchTreeNode<Leaf>] {
    if case .folder(let kids) = node.kind { return kids }
    return []
}
