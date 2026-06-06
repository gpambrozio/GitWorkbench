import SwiftUI

/// Host-supplied custom actions for file rows in the Changes tab, injected through the environment
/// (mirroring `\.workbenchTheme`) and read by `FileListRow`. Everything is opt-in: an unset closure
/// means "no behavior", and the row installs its AppKit mouse catcher only when at least one is set,
/// so a host that uses none pays nothing and behaves exactly as before. Populated by the public
/// `onChangesRightClick` / `onChangesRightClickPopover` / `onChangesDoubleClick` view modifiers below.
///
/// `@unchecked Sendable`: it stores host closures (not themselves `Sendable`), but the value is only
/// ever read in a SwiftUI view body and invoked from the row's AppKit mouse catcher — both on the main
/// actor — so there is no cross-thread sharing to guard. The annotation lets it back an `EnvironmentKey`
/// default under Swift 6's strict concurrency.
struct ChangesFileInteractions: @unchecked Sendable {
    /// Fired with the file's URL when its row is right-clicked.
    var onRightClick: ((URL) -> Void)?
    /// Builds the popover shown (anchored to the row) when it is right-clicked; a nil result shows nothing.
    var rightClickPopover: ((URL) -> AnyView?)?
    /// Fired with the file's URL when its row is double-clicked.
    var onDoubleClick: ((URL) -> Void)?

    var handlesRightClick: Bool { onRightClick != nil || rightClickPopover != nil }
    var isActive: Bool { handlesRightClick || onDoubleClick != nil }
}

private struct ChangesFileInteractionsKey: EnvironmentKey {
    static let defaultValue = ChangesFileInteractions()
}

extension EnvironmentValues {
    /// The Changes-tab custom actions injected by the host's view modifiers; `FileListRow` reads this.
    var changesFileInteractions: ChangesFileInteractions {
        get { self[ChangesFileInteractionsKey.self] }
        set { self[ChangesFileInteractionsKey.self] = newValue }
    }
}

public extension View {
    /// Perform a custom action when a file row in the **Changes** tab is right-clicked, receiving the
    /// clicked file's URL. Stacking is **additive**: applying this modifier more than once (e.g. from two
    /// independent feature layers) runs every action, rather than the last one winning. The URL is
    /// absolute when the host sets `WorkbenchConfiguration.repositoryURL`.
    func onChangesRightClick(_ action: @escaping (URL) -> Void) -> some View {
        transformEnvironment(\.changesFileInteractions) { interactions in
            let existing = interactions.onRightClick
            interactions.onRightClick = { url in existing?(url); action(url) }
        }
    }

    /// Show a popover anchored to a file row in the **Changes** tab when it is right-clicked. Return the
    /// popover's content for the clicked file's URL, or `nil` to show nothing for that file. When this
    /// modifier is stacked, the first overlay that returns a non-nil view wins (only one popover can be
    /// shown per row). Named distinctly from `onChangesRightClick(_:)` (the action overload) so the two
    /// don't resolve purely by closure return type, which made callers add an explicit `(URL)` annotation.
    func onChangesRightClickPopover<Content: View>(_ content: @escaping (URL) -> Content?) -> some View {
        transformEnvironment(\.changesFileInteractions) { interactions in
            let existing = interactions.rightClickPopover
            interactions.rightClickPopover = { url in existing?(url) ?? content(url).map { AnyView($0) } }
        }
    }

    /// Perform a custom action when a file row in the **Changes** tab is double-clicked, receiving the
    /// clicked file's URL. Stacking is **additive** (see `onChangesRightClick`). The URL is absolute when
    /// the host sets `WorkbenchConfiguration.repositoryURL`.
    func onChangesDoubleClick(_ action: @escaping (URL) -> Void) -> some View {
        transformEnvironment(\.changesFileInteractions) { interactions in
            let existing = interactions.onDoubleClick
            interactions.onDoubleClick = { url in existing?(url); action(url) }
        }
    }
}
