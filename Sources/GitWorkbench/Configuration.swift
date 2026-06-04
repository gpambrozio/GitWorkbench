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

/// How a host persists the workbench's resizable column widths. Supply one in `WorkbenchConfiguration`
/// to make column sizes survive relaunches and to control exactly where they live (UserDefaults, a
/// plist, your own settings store, iCloud, …); leave it `nil` for in-session-only layout. The component
/// never reaches into `UserDefaults` itself.
///
/// `key` is the configuration's `persistenceKey`, so a single store can back several embeddings by
/// routing on it. `widths` is an opaque `[columnID: points]` dictionary to round-trip; `save` is called
/// as the user drags, so debounce if your backing store is expensive.
public struct WorkbenchLayoutStore: Sendable {
    public var load: @Sendable (_ key: String) -> [String: CGFloat]?
    public var save: @Sendable (_ key: String, _ widths: [String: CGFloat]) -> Void

    public init(load: @escaping @Sendable (_ key: String) -> [String: CGFloat]?,
                save: @escaping @Sendable (_ key: String, _ widths: [String: CGFloat]) -> Void) {
        self.load = load
        self.save = save
    }
}

public struct WorkbenchConfiguration: Sendable {
    /// Draw the component's own toolbar bar (default). Set false if the host
    /// projects actions into a native NSToolbar / .toolbar instead.
    public var showsToolbar: Bool = true
    /// Default diff presentation when no per-repo preference is stored.
    public var defaultDiffMode: DiffMode = .split
    /// Which workspace view is shown first.
    public var initialView: WorkspaceView = .changes
    /// Identifies this embedding's saved state (passed to `layoutStore`). Distinct keys give each part
    /// of a host app its own independent column widths; nil falls back to an empty key.
    public var persistenceKey: String? = nil
    /// Host-supplied persistence for resizable column widths. nil → in-session only.
    public var layoutStore: WorkbenchLayoutStore? = nil
    /// Pane sizing (defaults + min constraints).
    public var layout: WorkbenchLayout = .init()
    /// Light-mode colors (the purple identity by default). Override to rebrand; set
    /// `theme.adoptsSystemAccent = true` to follow the macOS accent instead.
    public var theme: WorkbenchTheme = .standard
    /// Dark-mode colors, used when the environment color scheme is dark.
    public var darkTheme: WorkbenchTheme = .darkStandard

    public init() {}
}
