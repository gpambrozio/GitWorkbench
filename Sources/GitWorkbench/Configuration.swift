import CoreGraphics

public enum WorkspaceView: String, CaseIterable, Sendable, Hashable {
    case changes, history, stashes
}

public enum DiffMode: String, Sendable, Hashable {
    case unified, split
}

public struct WorkbenchLayout: Sendable, Hashable {
    public var railWidth: CGFloat = 218
    public var changesListWidth: CGFloat = 320
    public var historyListWidth: CGFloat = 360
    public var minRailWidth: CGFloat = 180
    public var minDiffWidth: CGFloat = 420
    public var toolbarHeight: CGFloat = 52
    public init() {}
}

public struct WorkbenchConfiguration: Sendable {
    /// Draw the component's own toolbar bar (default). Set false if the host
    /// projects actions into a native NSToolbar / .toolbar instead.
    public var showsToolbar: Bool = true
    /// Default diff presentation when no per-repo preference is stored.
    public var defaultDiffMode: DiffMode = .split
    /// Which workspace view is shown first.
    public var initialView: WorkspaceView = .changes
    /// Optional per-repository persistence key; nil disables persistence.
    public var persistenceKey: String? = nil
    /// Pane sizing.
    public var layout: WorkbenchLayout = .init()
    /// Visual theme (light identity by default).
    public var theme: WorkbenchTheme = .standard

    public init() {}
}
