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
