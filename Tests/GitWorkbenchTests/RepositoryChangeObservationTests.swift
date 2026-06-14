import XCTest
@testable import GitWorkbench

/// A provider whose repository-change stream the test drives, and which counts
/// how many times its status was loaded so we can observe auto-reloads.
private final class DrivableProvider: GitWorkbenchProvider, @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var _statusLoads = 0
    let offersChangeStream: Bool

    init(offersChangeStream: Bool = true) {
        self.offersChangeStream = offersChangeStream
        (stream, continuation) = AsyncStream<Void>.makeStream()
    }

    /// Number of times `loadStatus()` has been called (i.e. reloads).
    var statusLoads: Int { lock.withLock { _statusLoads } }
    /// Simulate an external repository change (commit, edit, branch switch).
    func emitChange() { continuation.yield(()) }

    // MARK: GitWorkbenchDataSource
    func repositoryChanges() -> AsyncStream<Void>? { offersChangeStream ? stream : nil }
    func loadStatus() async throws -> RepositoryStatus {
        lock.withLock { _statusLoads += 1 }
        return RepositoryStatus(repositoryName: "t", currentBranch: "main", upstream: nil,
                                ahead: 0, behind: 0, files: [], author: Author(name: "T", initials: "T"))
    }
    func loadHistory(of ref: String?, before: Commit.ID?, limit: Int) async throws -> [Commit] { [] }
    func loadStashes() async throws -> [Stash] { [] }
    func loadBranches() async throws -> [Branch] { [] }
    func loadRemoteBranches() async throws -> [RemoteBranch] { [] }
    func loadDiff(_ request: DiffRequest) async throws -> FileDiff { throw CancellationError() }

    // MARK: GitWorkbenchActionHandler (unused here)
    func stage(_ files: [FileChange]) async throws {}
    func unstage(_ files: [FileChange]) async throws {}
    func discard(_ file: FileChange) async throws {}
    func commit(message: String, staged: [FileChange]) async throws -> Commit { throw CancellationError() }
    func pull() async throws -> SyncResult { .init(ahead: 0, behind: 0, message: "") }
    func push() async throws -> SyncResult { .init(ahead: 0, behind: 0, message: "") }
    func fetch() async throws -> SyncResult { .init(ahead: 0, behind: 0, message: "") }
    func switchBranch(to branch: Branch) async throws {}
    func checkoutRemoteBranch(_ branch: RemoteBranch) async throws {}
    func applyStash(_ stash: Stash) async throws {}
    func popStash(_ stash: Stash) async throws {}
    func dropStash(_ stash: Stash) async throws {}
}

@MainActor
final class RepositoryChangeObservationTests: XCTestCase {

    /// Polls `condition` up to ~1s so we don't depend on exact task-scheduling timing.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    func test_storeAutoReloadsWhenProviderSignalsAChange() async {
        let provider = DrivableProvider(offersChangeStream: true)
        let store = GitWorkbenchStore(provider: provider)
        await store.reload()
        let baseline = provider.statusLoads          // first load

        provider.emitChange()                        // external change → store should reload itself

        let reloaded = await eventually { provider.statusLoads > baseline }
        XCTAssertTrue(reloaded, "store should reload automatically when the provider signals a repository change")
    }

    func test_noAutoReloadWhenProviderOffersNoStream() async {
        let provider = DrivableProvider(offersChangeStream: false)   // mirrors MockGitProvider's default
        let store = GitWorkbenchStore(provider: provider)
        await store.reload()
        let baseline = provider.statusLoads

        provider.emitChange()                        // nothing is subscribed; must be ignored

        // Give any (incorrect) observation a chance to fire, then assert it didn't.
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(provider.statusLoads, baseline, "without a change stream the store must not auto-reload")
    }
}
