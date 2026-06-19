import Foundation
import Observation

/// The single source of UI truth. Created by the host with a provider; the view observes it.
///
/// `@Observable`, so a host can observe derived state — most usefully ``summary`` — directly from
/// the store it already holds, without mounting ``GitWorkbenchView``. Combined with the provider's
/// repository-change stream (which keeps ``state`` fresh on its own), that makes the store a live,
/// headless source for host chrome like a badge, sidebar branch, or menu-bar item.
@MainActor
@Observable
public final class GitWorkbenchStore {
    public private(set) var state: WorkbenchState
    /// A host can recolor at runtime (see `setTheme`); other fields are set once at init.
    public private(set) var configuration: WorkbenchConfiguration

    /// Becomes `true` after the first successful status load, so ``summary`` can stay `nil` for the
    /// pre-load placeholder rather than reporting an empty repository.
    public private(set) var hasLoaded = false

    // MARK: Branch-rail collapse state

    //
    // The branch rail's expand/collapse state lives on the store — not in the `WorkspaceRail` view's
    // `@State` — so it outlives the view being torn down and rebuilt. A host that swaps
    // `GitWorkbenchView` out and back on the *same* store (e.g. switching tabs or sessions) keeps the
    // user's expanded folders instead of resetting to the collapse-all-but-current-branch default,
    // exactly as the selected file, active view, and diff already survive on the store. Only
    // `railCollapsed` is read by the view (and so is observed); the other three are reconcile
    // bookkeeping the view never reads, so they skip observation.

    /// Collapsed folders, keyed by namespaced slash-path (e.g. "L:feat" or "R:origin:feat"). Mutated
    /// through ``toggleRailFolder(_:)`` and ``applyRailCollapseDefaults(allFolders:currentBranch:headPath:repo:)``.
    public private(set) var railCollapsed: Set<String> = []
    /// Folders present at the last reconcile, so a branch-list change collapses only the *newly
    /// appeared* folders without disturbing the user's existing toggles.
    @ObservationIgnored private var railKnownFolders: Set<String> = []
    /// The repo the collapse state was initialized for; a different repo triggers a fresh default
    /// (collapse-all-but-current-branch) rather than reconciling against unrelated folders.
    @ObservationIgnored private var railInitializedRepo: String?
    /// The last current branch we expanded to, so a *change* of HEAD (switching branches) reveals the
    /// new branch by expanding its path — without re-expanding it on unrelated refreshes.
    @ObservationIgnored private var railCurrentHead: String?

    @ObservationIgnored private let provider: any GitWorkbenchProvider

    /// In-flight diff load for the current selection (awaitable in tests).
    @ObservationIgnored private(set) var diffTask: Task<Void, Never>?

    /// Long-lived subscription to the provider's repository-change stream, so external
    /// edits/commits reload the store automatically. nil until the first `reload()` starts
    /// it; cancelled on deinit (which tears down the provider's underlying watcher).
    @ObservationIgnored private var changeObservationTask: Task<Void, Never>?

    deinit { changeObservationTask?.cancel() }

    public init(provider: any GitWorkbenchProvider, configuration: WorkbenchConfiguration = .init()) {
        self.provider = provider
        self.configuration = configuration
        let emptyRepo = RepositoryStatus(
            repositoryName: "", currentBranch: "", upstream: nil,
            ahead: 0, behind: 0, files: [], author: Author(name: "", initials: "")
        )
        var initial = WorkbenchState(repo: emptyRepo)
        initial.activeView = configuration.initialView
        // Restore the saved diff presentation (same host store as column widths), falling
        // back to the configured default when nothing is persisted.
        initial.diffMode = Self.loadDiffMode(configuration) ?? configuration.defaultDiffMode
        state = initial
    }

    // MARK: Diff-mode persistence

    //
    // Persisted through the host's `WorkbenchLayoutStore` — the same mechanism as the
    // resizable column widths — under a key sibling to the widths' so the two never clobber
    // each other. Encoded numerically because the store round-trips `[String: CGFloat]`.

    private static func diffModeKey(_ configuration: WorkbenchConfiguration) -> String {
        "\(configuration.persistenceKey ?? "").diffMode"
    }

    private static func loadDiffMode(_ configuration: WorkbenchConfiguration) -> DiffMode? {
        guard let raw = configuration.layoutStore?.load(diffModeKey(configuration))?["mode"] else { return nil }
        return raw == 0 ? .unified : .split
    }

    private func saveDiffMode(_ mode: DiffMode) {
        configuration.layoutStore?.save(Self.diffModeKey(configuration), ["mode": mode == .split ? 1 : 0])
    }

    // MARK: Branch-rail collapse

    /// Toggle one branch-rail folder's collapsed state (a chevron click in the rail).
    public func toggleRailFolder(_ key: String) {
        if railCollapsed.contains(key) { railCollapsed.remove(key) } else { railCollapsed.insert(key) }
    }

    /// Reconcile the rail's collapse state against the current set of folders, called by the rail when
    /// the branch list or HEAD changes (and on first appearance). The first time we see a repo, collapse
    /// everything except `headPath` (the path to the current branch and its tracked upstream). On later
    /// branch-list changes within the same repo, preserve the user's toggles and only collapse the
    /// folders that newly appeared (see ``reconcileCollapsed(previous:knownFolders:allFolders:)``) — but
    /// when HEAD itself changed (the user switched branches), expand `headPath` so the new branch shows.
    ///
    /// Because this state lives on the store rather than the view, returning to a session whose store is
    /// still alive takes the reconcile path (which preserves toggles) instead of re-running the first-time
    /// collapse-all default — so manual expansions survive a tab/session switch.
    public func applyRailCollapseDefaults(allFolders: Set<String>, currentBranch: String, headPath: [String], repo: String) {
        let headChanged = railCurrentHead != currentBranch
        if railInitializedRepo != repo {
            railInitializedRepo = repo
            railCollapsed = allFolders.subtracting(headPath)
        } else {
            railCollapsed = reconcileCollapsed(previous: railCollapsed, knownFolders: railKnownFolders, allFolders: allFolders)
            if headChanged {
                railCollapsed.subtract(headPath)
            }
        }
        railKnownFolders = allFolders
        railCurrentHead = currentBranch
    }

    // MARK: Loading

    /// Re-pull status, branches, remote branches, history, and stashes.
    public func reload() async {
        do {
            async let status = provider.loadStatus()
            async let branches = provider.loadBranches()
            async let remoteBranches = provider.loadRemoteBranches()
            async let stashes = provider.loadStashes()
            let (s, b, rb, st) = try await (status, branches, remoteBranches, stashes)
            state.repo = s
            state.branches = b
            state.remoteBranches = rb
            state.stashes = st
            hasLoaded = true
        } catch {
            setError(error)
        }
        await reloadHistory()
        observeRepositoryChangesIfNeeded()
    }

    // MARK: Summary

    /// A stable snapshot of the repository — file counts, conflicts, push/pull state, branch, churn —
    /// for driving host chrome (a badge, sidebar branch, menu-bar item, window title) straight from
    /// the store, without mounting ``GitWorkbenchView``.
    ///
    /// `nil` until the first successful load completes, so a host never has to special-case the empty
    /// placeholder. Because the store is `@Observable` and reloads itself from the provider's
    /// repository-change stream, reading this in a SwiftUI `body` (or via `withObservationTracking`)
    /// updates live as the working tree changes — the headless equivalent of the
    /// `onRepositorySummaryChange(_:)` view modifier.
    public var summary: RepositorySummary? {
        hasLoaded ? RepositorySummary(state: state) : nil
    }

    /// Subscribe to the provider's repository-change stream (if it offers one) so external
    /// edits/commits reload the store on their own. Idempotent: starts at most one
    /// subscription, on the first reload. Each emission triggers a full `reload()`.
    private func observeRepositoryChangesIfNeeded() {
        guard changeObservationTask == nil, let changes = provider.repositoryChanges() else { return }
        changeObservationTask = Task { [weak self] in
            for await _ in changes {
                await self?.reloadFromExternalChange()
            }
        }
    }

    /// Reload after an external on-disk change, also refreshing the open working-tree diff so
    /// editing the file you're viewing updates the diff pane, not just the file list. (History
    /// and stash diffs are immutable, so only the Changes selection can go stale.)
    private func reloadFromExternalChange() async {
        await reload()
        if state.activeView == .changes, let id = state.selectedFileID {
            select(file: id)
        }
    }

    /// Loads commits for the branch being viewed in History (`historyBranch`; nil = current HEAD),
    /// falling back to HEAD if that ref has gone away (e.g. the branch was deleted externally) so a
    /// background reload can't get stuck erroring.
    private func reloadHistory() async {
        do {
            state.commits = try await provider.loadHistory(of: state.historyBranch, before: nil, limit: 50)
        } catch {
            guard state.historyBranch != nil else { setError(error); return }
            state.historyBranch = nil
            state.commits = (try? await provider.loadHistory(of: nil, before: nil, limit: 50)) ?? []
        }
    }

    /// Show a branch's history (single-click on a branch in the rail): switch to History, load that
    /// branch's commits, and select its tip. `historyBranch` persists across reloads.
    public func showHistory(of branch: Branch) async {
        await showHistory(ofRef: branch.name)
    }

    /// Show a remote branch's history. The full ref (e.g. `origin/feat/x`) is a valid revision for
    /// `git log`, and doubles as the selection key in the rail.
    public func showHistory(of branch: RemoteBranch) async {
        await showHistory(ofRef: branch.id)
    }

    private func showHistory(ofRef ref: String) async {
        state.activeView = .history
        state.historyBranch = ref
        state.isLoadingHistory = true
        do {
            state.commits = try await provider.loadHistory(of: ref, before: nil, limit: 50)
            state.isLoadingHistory = false
            if let first = state.commits.first {
                await selectCommit(first.id)
            } else {
                state.selectedCommitID = nil
                state.selectedCommitFileID = nil
                state.currentDiff = nil
            }
        } catch {
            state.isLoadingHistory = false
            setError(error)
        }
    }

    // MARK: Selection (synchronous intents)

    public func select(_ view: WorkspaceView) { state.activeView = view }
    public func setDiffMode(_ mode: DiffMode) {
        state.diffMode = mode
        saveDiffMode(mode)
    }

    public func setCommitMessage(_ text: String) { state.commitMessage = text }

    /// Swap the light + dark color themes at runtime (recolors immediately, no reload).
    public func setTheme(light: WorkbenchTheme, dark: WorkbenchTheme) {
        configuration.theme = light
        configuration.darkTheme = dark
    }

    public func select(file id: FileChange.ID) {
        state.selectedFileID = id
        guard let file = state.repo.files.first(where: { $0.id == id }) else {
            state.currentDiff = nil
            return
        }
        let context: DiffRequest.Context = .workingTree(staged: file.isStaged)
        diffTask?.cancel()
        diffTask = Task { [weak self] in
            await self?.loadDiff(for: file, context: context)
        }
    }

    // MARK: Internal helpers (used here and by the intent extensions)

    /// Loads a diff for `file` in `context` and stores it (nil on failure — the pane shows empty).
    func loadDiff(for file: FileChange, context: DiffRequest.Context) async {
        let request = DiffRequest(file: file, context: context, mode: state.diffMode)
        let diff = try? await provider.loadDiff(request)
        if !Task.isCancelled { state.currentDiff = diff }
    }

    /// Maps an error to a toast message and shows it.
    func setError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        state.toast = .error(message)
    }

    // MARK: Convenience

    /// A fully-seeded store for previews and demos (backed by the mock).
    @MainActor public static var preview: GitWorkbenchStore {
        let store = GitWorkbenchStore(provider: MockGitProvider())
        var seeded = Fixtures.initialState
        if let first = seeded.repo.files.first {
            seeded.selectedFileID = first.id
            seeded.currentDiff = FixtureDiffs.diff(for: first, context: .workingTree(staged: first.isStaged))
        }
        store.state = seeded
        return store
    }
}

// MARK: - Changes intents

public extension GitWorkbenchStore {
    func toggleStage(_ id: FileChange.ID) async {
        guard let idx = state.repo.files.firstIndex(where: { $0.id == id }) else { return }
        let original = state.repo.files[idx]
        let nowStaged = !original.isStaged
        state.repo.files[idx].isStaged = nowStaged // optimistic
        do {
            if nowStaged { try await provider.stage([original]) }
            else { try await provider.unstage([original]) }
        } catch {
            if let i = state.repo.files.firstIndex(where: { $0.id == id }) {
                state.repo.files[i].isStaged = original.isStaged // rollback
            }
            setError(error)
        }
    }

    func stageAll() async {
        let targets = state.unstaged
        guard !targets.isEmpty else { return }
        let snapshot = state.repo.files
        for i in state.repo.files.indices {
            state.repo.files[i].isStaged = true
        }
        do { try await provider.stage(targets) }
        catch { state.repo.files = snapshot; setError(error) }
    }

    func unstageAll() async {
        let targets = state.staged
        guard !targets.isEmpty else { return }
        let snapshot = state.repo.files
        for i in state.repo.files.indices {
            state.repo.files[i].isStaged = false
        }
        do { try await provider.unstage(targets) }
        catch { state.repo.files = snapshot; setError(error) }
    }

    func requestDiscard(_ id: FileChange.ID) {
        state.pendingDiscard = state.repo.files.first { $0.id == id }
    }

    func cancelDiscard() { state.pendingDiscard = nil }

    func confirmDiscard() async {
        guard let file = state.pendingDiscard else { return }
        state.pendingDiscard = nil
        do {
            try await provider.discard(file)
            state.repo.files.removeAll { $0.id == file.id }
            if state.selectedFileID == file.id {
                state.selectedFileID = nil
                state.currentDiff = nil
            }
            state.toast = .success("Discarded changes in \(file.name)")
        } catch {
            setError(error)
        }
    }

    func commit() async {
        guard state.canCommit else { return }
        let staged = state.staged
        let message = state.commitMessage
        do {
            let newCommit = try await provider.commit(message: message, staged: staged)
            state.repo.files.removeAll { $0.isStaged }
            state.commitMessage = ""
            state.repo.ahead += 1
            state.commits.insert(newCommit, at: 0)
            state.selectedFileID = nil
            state.currentDiff = nil
            state.toast = .success("Committed \(staged.count) file(s) \u{00B7} \u{201C}\(newCommit.summary)\u{201D}")
        } catch {
            setError(error)
        }
    }
}

// MARK: - Sync & branch intents

public extension GitWorkbenchStore {
    func pull() async { await runSync(.pull) }
    func push() async { await runSync(.push) }
    func fetch() async { await runSync(.fetch) }

    private enum SyncKind { case pull, push, fetch }

    private func runSync(_ kind: SyncKind) async {
        guard !state.isBusy else { return }
        state.isBusy = true
        switch kind {
        case .pull: state.toast = .progress("Pulling from origin\u{2026}")
        case .push: state.toast = .progress("Pushing to origin\u{2026}")
        case .fetch: state.toast = .progress("Fetching from origin\u{2026}")
        }
        do {
            let result: SyncResult
            switch kind {
            case .pull: result = try await provider.pull()
            case .push: result = try await provider.push()
            case .fetch: result = try await provider.fetch()
            }
            state.repo.ahead = result.ahead
            state.repo.behind = result.behind
            // A pull moves HEAD forward with the fetched commits, so the History view's
            // commit list is now stale — refresh it.
            if kind == .pull { await reloadHistory() }
            state.isBusy = false
            state.toast = .success(result.message)
        } catch {
            state.isBusy = false
            setError(mapSyncError(error, kind: kind))
        }
    }

    private func mapSyncError(_ error: Error, kind: SyncKind) -> Error {
        guard kind == .push else { return error }
        let desc = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription).lowercased()
        if desc.contains("reject") || desc.contains("non-fast-forward") {
            return WorkbenchMessageError("Push rejected \u{2014} pull first")
        }
        return error
    }

    func switchBranch(to branch: Branch) async {
        do {
            try await provider.switchBranch(to: branch)
            state.historyBranch = nil // history follows the new current branch
            await reload()
            state.toast = .success("Switched to \(branch.name)")
        } catch {
            setError(error)
        }
    }

    /// Check out a remote branch locally (double-click in the rail), tracking it. The new local
    /// branch becomes HEAD, so history follows it like a plain switch.
    func checkoutRemoteBranch(_ branch: RemoteBranch) async {
        do {
            try await provider.checkoutRemoteBranch(branch)
            state.historyBranch = nil // history follows the new current branch
            await reload()
            state.toast = .success("Checked out \(branch.name)")
        } catch {
            setError(error)
        }
    }
}

/// A simple `LocalizedError` carrying a ready-made message.
struct WorkbenchMessageError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Chrome intents

public extension GitWorkbenchStore {
    func dismissToast() { state.toast = nil }
}

// MARK: - Detail-pane intents

public extension GitWorkbenchStore {
    func selectCommitFile(_ fileID: FileChange.ID) {
        state.selectedCommitFileID = fileID
        guard let commitID = state.selectedCommitID,
              let file = state.commits.first(where: { $0.id == commitID })?.files.first(where: { $0.id == fileID })
        else { return }
        diffTask?.cancel()
        diffTask = Task { [weak self] in await self?.loadDiff(for: file, context: .commit(commitID)) }
    }

    func selectStashFile(_ fileID: FileChange.ID) {
        state.selectedStashFileID = fileID
        guard let stashID = state.selectedStashID,
              let file = state.stashes.first(where: { $0.id == stashID })?.files.first(where: { $0.id == fileID })
        else { return }
        diffTask?.cancel()
        diffTask = Task { [weak self] in await self?.loadDiff(for: file, context: .stash(stashID)) }
    }

    func showToast(_ message: String, style: Toast.Style = .success) {
        state.toast = Toast(message: message, style: style)
    }
}

// MARK: - History & stash intents

public extension GitWorkbenchStore {
    func selectCommit(_ id: Commit.ID) async {
        state.selectedCommitID = id
        guard let commit = state.commits.first(where: { $0.id == id }) else { return }
        state.selectedCommitFileID = commit.files.first?.id
        if let first = commit.files.first {
            await loadDiff(for: first, context: .commit(id))
        } else {
            state.currentDiff = nil
        }
    }

    func selectStash(_ id: Stash.ID) async {
        state.selectedStashID = id
        guard let stash = state.stashes.first(where: { $0.id == id }) else { return }
        state.selectedStashFileID = stash.files.first?.id
        if let first = stash.files.first {
            await loadDiff(for: first, context: .stash(id))
        } else {
            state.currentDiff = nil
        }
    }

    func applyStash(_ id: Stash.ID) async {
        guard let stash = state.stashes.first(where: { $0.id == id }) else { return }
        do {
            try await provider.applyStash(stash)
            state.toast = .success("Applied \(stash.ref) to working tree")
        } catch {
            setError(error)
        }
    }

    func popStash(_ id: Stash.ID) async {
        guard let stash = state.stashes.first(where: { $0.id == id }) else { return }
        do {
            try await provider.popStash(stash)
            removeStashAndReselect(id)
            state.toast = .success("Popped \(stash.ref) \u{2014} \u{201C}\(stash.message)\u{201D}")
        } catch {
            setError(error)
        }
    }

    func dropStash(_ id: Stash.ID) async {
        guard let stash = state.stashes.first(where: { $0.id == id }) else { return }
        do {
            try await provider.dropStash(stash)
            removeStashAndReselect(id)
            state.toast = .success("Dropped \(stash.ref) \u{2014} \u{201C}\(stash.message)\u{201D}")
        } catch {
            setError(error)
        }
    }

    private func removeStashAndReselect(_ id: Stash.ID) {
        guard let idx = state.stashes.firstIndex(where: { $0.id == id }) else { return }
        state.stashes.remove(at: idx)
        guard !state.stashes.isEmpty else {
            state.selectedStashID = nil
            state.selectedStashFileID = nil
            state.currentDiff = nil
            return
        }
        let nextIdx = min(idx, state.stashes.count - 1)
        let next = state.stashes[nextIdx]
        state.selectedStashID = next.id
        state.selectedStashFileID = next.files.first?.id
        if let first = next.files.first {
            diffTask?.cancel()
            diffTask = Task { [weak self] in
                await self?.loadDiff(for: first, context: .stash(next.id))
            }
        } else {
            state.currentDiff = nil
        }
    }
}
