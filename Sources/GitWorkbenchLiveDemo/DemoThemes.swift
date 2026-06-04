import SwiftUI
import GitWorkbench

/// A named light + dark theme pair for the demo's Theme menu. Shows how a host builds themes off the
/// built-in identity — these are accent rebrands, but any of `WorkbenchTheme`'s ~30 tokens can be set.
struct DemoTheme: Identifiable {
    var id: String { name }
    let name: String
    let light: WorkbenchTheme
    let dark: WorkbenchTheme

    /// An accent-only rebrand of the built-in light/dark identity.
    static func accent(_ name: String, _ color: Color) -> DemoTheme {
        DemoTheme(name: name, light: .standard.withAccent(color), dark: .darkStandard.withAccent(color))
    }
}

enum DemoThemes {
    static let all: [DemoTheme] = [
        DemoTheme(name: "Purple", light: .standard, dark: .darkStandard),   // the built-in identity
        .accent("Ocean",  Color(red: 0.13, green: 0.51, blue: 0.93)),
        .accent("Forest", Color(red: 0.18, green: 0.62, blue: 0.38)),
        .accent("Sunset", Color(red: 0.95, green: 0.49, blue: 0.20)),
        .accent("Rose",   Color(red: 0.89, green: 0.22, blue: 0.46)),
    ]

    static func named(_ name: String) -> DemoTheme {
        all.first { $0.name == name } ?? all[0]
    }
}
