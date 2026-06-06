import SwiftUI

/// Host-supplied observer of the repository's `RepositorySummary`, injected through the environment
/// (mirroring `\.workbenchTheme` and `\.changesFileInteractions`) and read by `GitWorkbenchView`. It is
/// opt-in: an unset closure means the view does no extra work. Populated by the public
/// `onRepositorySummaryChange(_:)` view modifier below.
///
/// `@unchecked Sendable`: it stores a host closure (not itself `Sendable`), but the value is only ever
/// read in a SwiftUI view body and invoked from `.onChange` — both on the main actor — so there is no
/// cross-thread sharing to guard. The annotation lets it back an `EnvironmentKey` default under Swift 6's
/// strict concurrency.
struct RepositorySummaryObserver: @unchecked Sendable {
    /// Fired with the current summary on appear and then once per distinct summary thereafter.
    var onChange: ((RepositorySummary) -> Void)?
}

private struct RepositorySummaryObserverKey: EnvironmentKey {
    static let defaultValue = RepositorySummaryObserver()
}

extension EnvironmentValues {
    /// The host's repository-summary observer injected by `onRepositorySummaryChange`; `GitWorkbenchView`
    /// reads this and drives it from `.onChange`.
    var repositorySummaryObserver: RepositorySummaryObserver {
        get { self[RepositorySummaryObserverKey.self] }
        set { self[RepositorySummaryObserverKey.self] = newValue }
    }
}

public extension View {
    /// Observe the repository's `RepositorySummary` — file counts, conflicts, push/pull state, branch,
    /// churn, and convenience flags — to drive your own chrome (menu-bar item, dock badge, window title,
    /// sidebar badge) without running `git` again or reaching into the store.
    ///
    /// The closure is called once with the current summary when the view appears (and after a repository
    /// swap re-mounts it), then once each time the summary actually changes. Identical summaries are
    /// deduplicated, so it never fires twice for the same value.
    ///
    /// Stacking is **additive**: applying this modifier more than once (e.g. from two independent feature
    /// layers) runs every observer, rather than the last one winning.
    func onRepositorySummaryChange(_ action: @escaping (RepositorySummary) -> Void) -> some View {
        transformEnvironment(\.repositorySummaryObserver) { observer in
            let existing = observer.onChange
            observer.onChange = { summary in existing?(summary); action(summary) }
        }
    }
}
