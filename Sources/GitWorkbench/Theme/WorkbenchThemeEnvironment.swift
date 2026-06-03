import SwiftUI

private struct WorkbenchThemeKey: EnvironmentKey {
    static let defaultValue: WorkbenchTheme = .standard
}

extension EnvironmentValues {
    /// The resolved theme injected by the root view; primitives read this.
    var workbenchTheme: WorkbenchTheme {
        get { self[WorkbenchThemeKey.self] }
        set { self[WorkbenchThemeKey.self] = newValue }
    }
}

extension View {
    /// Injects a resolved `WorkbenchTheme` for descendant primitives.
    func workbenchTheme(_ theme: WorkbenchTheme) -> some View {
        environment(\.workbenchTheme, theme)
    }
}
