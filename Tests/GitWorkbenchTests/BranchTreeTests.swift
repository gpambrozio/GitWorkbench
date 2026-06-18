import XCTest
@testable import GitWorkbench

final class BranchTreeTests: XCTestCase {
    func test_emptyInputMakesEmptyTree() {
        XCTAssertTrue(makeBranchTree([String]()) { $0 }.isEmpty)
    }

    func test_flatLeavesSortCaseInsensitively() {
        let tree = makeBranchTree(["main", "develop", "zeta"]) { $0 }
        XCTAssertEqual(tree.map(\.name), ["develop", "main", "zeta"])
        XCTAssertEqual(tree.map(\.id), ["develop", "main", "zeta"])
        XCTAssertTrue(tree.allSatisfy(isLeaf))
    }

    func test_sortIsCaseInsensitive() {
        // Uppercase must not sort ahead of lowercase the way raw ASCII ordering would.
        let tree = makeBranchTree(["Zebra", "apple", "Mango"]) { $0 }
        XCTAssertEqual(tree.map(\.name), ["apple", "Mango", "Zebra"])
    }

    func test_siblingsInterleaveAndSortCaseInsensitively() {
        let tree = makeBranchTree(["claude/issue-597", "claude/issue-600", "docs/x", "main"]) { $0 }
        // Folders and the `main` leaf merge into one sorted list (no leaves-before-folders grouping).
        XCTAssertEqual(tree.map(\.name), ["claude", "docs", "main"])
        XCTAssertEqual(tree.map(\.id), ["claude", "docs", "main"])
        XCTAssertTrue(isLeaf(tree[2]))

        let claude = children(tree[0])
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

    func test_foldersAndLeavesInterleaveWithinAFolder() {
        // Interleaving must also hold *inside* a folder: a leaf can sit between two folders by name.
        let tree = makeBranchTree(["a/z-fold/x", "a/m-leaf", "a/a-fold/y"]) { $0 }
        XCTAssertEqual(tree.map(\.name), ["a"])
        let a = children(tree[0])
        XCTAssertEqual(a.map(\.name), ["a-fold", "m-leaf", "z-fold"])
        XCTAssertFalse(isLeaf(a[0]))                 // a-fold is a folder
        XCTAssertTrue(isLeaf(a[1]))                  // m-leaf, a leaf, sits between two folders
        XCTAssertEqual(leafValue(a[1]), "a/m-leaf")
        XCTAssertFalse(isLeaf(a[2]))                 // z-fold is a folder
    }

    func test_extraSlashesCollapse() {
        // git never emits these, but the splitter must not produce empty segments or drop the ref.
        let tree = makeBranchTree(["a//b", "trailing/"]) { $0 }
        XCTAssertEqual(tree.map(\.name), ["a", "trailing"])  // "trailing/" -> single leaf "trailing"
        XCTAssertEqual(children(tree[0]).map(\.id), ["a/b"])
    }

    // MARK: - Default-branch pinning

    func test_defaultBranchNameHeuristicPrefersByPriority() {
        XCTAssertEqual(defaultBranchName(among: ["develop", "feat/x", "ga/y"]), "develop")
        XCTAssertEqual(defaultBranchName(among: ["develop", "master", "main"]), "main")    // main wins
        XCTAssertEqual(defaultBranchName(among: ["develop", "master"]), "master")          // master beats develop
        XCTAssertNil(defaultBranchName(among: ["feat/x", "topic", "ga/y"]))
    }

    func test_defaultBranchNameMatchIsCaseInsensitiveButKeepsCasing() {
        XCTAssertEqual(defaultBranchName(among: ["Main"]), "Main")
    }

    func test_pinnedToTopFloatsDefaultBranchAheadOfSortedSiblings() {
        let tree = makeBranchTree(["ga/x", "develop", "auto/y"], pinnedToTop: "develop") { $0 }
        // Without the pin the sorted root would be auto, develop, ga; the pin floats develop first.
        XCTAssertEqual(tree.map(\.name), ["develop", "auto", "ga"])
        XCTAssertTrue(isLeaf(tree[0]))
    }

    func test_pinnedToTopOnlyReordersRootAndChildrenStaySorted() {
        let tree = makeBranchTree(["ga/zebra", "ga/apple", "main"], pinnedToTop: "main") { $0 }
        XCTAssertEqual(tree.map(\.name), ["main", "ga"])              // main pinned, ga follows
        XCTAssertEqual(children(tree[1]).map(\.name), ["apple", "zebra"])  // children still sorted
    }

    func test_pinnedToTopAbsentLeavesSortUnchanged() {
        let tree = makeBranchTree(["ga/y", "auto/x"], pinnedToTop: "develop") { $0 }
        XCTAssertEqual(tree.map(\.name), ["auto", "ga"])
    }

    // MARK: - Fixtures

    func test_localBranchFixturesCarryTheBranchValue() {
        let tree = makeBranchTree(Fixtures.branches) { $0.name }
        // provider order main, develop, feat/auto-sync, fix/log-levels -> one interleaved sorted list.
        XCTAssertEqual(tree.map(\.name), ["develop", "feat", "fix", "main"])
        XCTAssertEqual(leafValue(tree[3])?.name, "main")

        let feat = children(tree[1])
        XCTAssertEqual(feat.map(\.name), ["auto-sync"])
        XCTAssertEqual(leafValue(feat[0])?.name, "feat/auto-sync")
        XCTAssertEqual(leafValue(feat[0])?.isCurrent, true)
        XCTAssertEqual(children(tree[2]).map(\.name), ["log-levels"])
    }

    func test_remoteBranchFixturesKeepFullRefIDs() {
        let origin = Fixtures.remoteBranches.filter { $0.remote == "origin" }
        let tree = makeBranchTree(origin) { $0.name }
        XCTAssertEqual(tree.map(\.name), ["develop", "feat", "main", "release"])

        let feat = children(tree[1])
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
