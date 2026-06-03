import Combine
import Foundation

/// The single source of UI truth. Created by the host with a provider; the view observes it.
@MainActor
public final class GitWorkbenchStore: ObservableObject {

    @Published public private(set) var state: WorkbenchState
    public let configuration: WorkbenchConfiguration

    private let provider: any GitWorkbenchProvider

    /// In-flight diff load for the current selection (awaitable in tests).
    private(set) var diffTask: Task<Void, Never>?

    public init(provider: any GitWorkbenchProvider, configuration: WorkbenchConfiguration = .init()) {
        self.provider = provider
        self.configuration = configuration
        let emptyRepo = RepositoryStatus(
            repositoryName: "", currentBranch: "", upstream: nil,
            ahead: 0, behind: 0, files: [], author: Author(name: "", initials: "")
        )
        var initial = WorkbenchState(repo: emptyRepo)
        initial.activeView = configuration.initialView
        initial.diffMode = configuration.defaultDiffMode
        self.state = initial
    }

    // MARK: Loading

    /// Re-pull status, branches, history, and stashes.
    public func reload() async {
        do {
            async let status = provider.loadStatus()
            async let branches = provider.loadBranches()
            async let history = provider.loadHistory(before: nil, limit: 50)
            async let stashes = provider.loadStashes()
            let (s, b, h, st) = try await (status, branches, history, stashes)
            state.repo = s
            state.branches = b
            state.commits = h
            state.stashes = st
        } catch {
            setError(error)
        }
    }

    // MARK: Selection (synchronous intents)

    public func select(_ view: WorkspaceView) { state.activeView = view }
    public func setDiffMode(_ mode: DiffMode) { state.diffMode = mode }
    public func setCommitMessage(_ text: String) { state.commitMessage = text }

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

extension GitWorkbenchStore {

    public func toggleStage(_ id: FileChange.ID) async {
        guard let idx = state.repo.files.firstIndex(where: { $0.id == id }) else { return }
        let original = state.repo.files[idx]
        let nowStaged = !original.isStaged
        state.repo.files[idx].isStaged = nowStaged   // optimistic
        do {
            if nowStaged { try await provider.stage([original]) }
            else { try await provider.unstage([original]) }
        } catch {
            if let i = state.repo.files.firstIndex(where: { $0.id == id }) {
                state.repo.files[i].isStaged = original.isStaged   // rollback
            }
            setError(error)
        }
    }

    public func stageAll() async {
        let targets = state.unstaged
        guard !targets.isEmpty else { return }
        let snapshot = state.repo.files
        for i in state.repo.files.indices { state.repo.files[i].isStaged = true }
        do { try await provider.stage(targets) }
        catch { state.repo.files = snapshot; setError(error) }
    }

    public func unstageAll() async {
        let targets = state.staged
        guard !targets.isEmpty else { return }
        let snapshot = state.repo.files
        for i in state.repo.files.indices { state.repo.files[i].isStaged = false }
        do { try await provider.unstage(targets) }
        catch { state.repo.files = snapshot; setError(error) }
    }

    public func requestDiscard(_ id: FileChange.ID) {
        state.pendingDiscard = state.repo.files.first { $0.id == id }
    }

    public func cancelDiscard() { state.pendingDiscard = nil }

    public func confirmDiscard() async {
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

    public func commit() async {
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

extension GitWorkbenchStore {

    public func pull() async { await runSync(.pull) }
    public func push() async { await runSync(.push) }
    public func fetch() async { await runSync(.fetch) }

    private enum SyncKind { case pull, push, fetch }

    private func runSync(_ kind: SyncKind) async {
        guard !state.isBusy else { return }
        state.isBusy = true
        switch kind {
        case .pull:  state.toast = .progress("Pulling from origin\u{2026}")
        case .push:  state.toast = .progress("Pushing to origin\u{2026}")
        case .fetch: state.toast = .progress("Fetching from origin\u{2026}")
        }
        do {
            let result: SyncResult
            switch kind {
            case .pull:  result = try await provider.pull()
            case .push:  result = try await provider.push()
            case .fetch: result = try await provider.fetch()
            }
            state.repo.ahead = result.ahead
            state.repo.behind = result.behind
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

    public func switchBranch(to branch: Branch) async {
        state.branchMenuOpen = false
        do {
            try await provider.switchBranch(to: branch)
            await reload()
            state.toast = .success("Switched to \(branch.name)")
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
