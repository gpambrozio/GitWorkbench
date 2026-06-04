import SwiftUI
import AppKit
import GitWorkbench
import GitWorkbenchGitKit

/// Holds the live store and lets the user point it at a different repository at runtime. The store is
/// swapped wholesale on open (the core provider is immutable by design), and views observe this model so
/// they rebuild against the new store. Backed by a real `CLIGitProvider`; a `RepositoryWatcher` keeps it
/// in sync with on-disk changes.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var store: GitWorkbenchStore
    @Published private(set) var themeName: String
    private(set) var repoURL: URL
    private var watcher: RepositoryWatcher?

    private static let themeKey = "LiveDemo.theme"

    private init() {
        let url = Self.initialRepoURL
        let theme = UserDefaults.standard.string(forKey: Self.themeKey) ?? DemoThemes.all[0].name
        repoURL = url
        themeName = theme
        store = Self.makeStore(for: url, themeName: theme)
    }

    /// A store whose configuration opts into persistence (so resized column widths survive relaunches)
    /// and carries the selected sample theme.
    private static func makeStore(for url: URL, themeName: String) -> GitWorkbenchStore {
        var configuration = WorkbenchConfiguration()
        configuration.persistenceKey = "LiveDemo"
        configuration.layoutStore = .userDefaults
        let theme = DemoThemes.named(themeName)
        configuration.theme = theme.light
        configuration.darkTheme = theme.dark
        return GitWorkbenchStore(provider: CLIGitProvider(repositoryURL: url), configuration: configuration)
    }

    /// Switch the active sample theme — recolors instantly (no reload) and persists the choice.
    func applyTheme(named name: String) {
        guard name != themeName else { return }
        themeName = name
        UserDefaults.standard.set(name, forKey: Self.themeKey)
        let theme = DemoThemes.named(name)
        store.setTheme(light: theme.light, dark: theme.dark)
    }

    /// Initial load + start watching (interactive mode).
    func start() async {
        await store.reload()
        startWatching()
    }

    /// Prompt for a folder and, if chosen, open it as the repository.
    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a git repository folder"
        panel.prompt = "Open"
        panel.directoryURL = repoURL
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    /// Point the demo at `url`: swap in a fresh store, reload, and re-aim the filesystem watcher.
    func open(_ url: URL) {
        guard url != repoURL else { return }
        watcher?.stop()
        watcher = nil
        repoURL = url
        store = Self.makeStore(for: url, themeName: themeName)
        Task { @MainActor in
            await store.reload()
            startWatching()
        }
    }

    /// Watch the working tree and reload on any change (debounced), so external edits / commits / stashes
    /// show up without relaunching. Also refreshes the open working-tree diff via the public `select`
    /// intent, so editing the file you're viewing updates the diff pane, not just the file list.
    private func startWatching() {
        let watcher = RepositoryWatcher(url: repoURL) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.store.reload()
                if self.store.state.activeView == .changes, let id = self.store.state.selectedFileID {
                    self.store.select(file: id)
                }
            }
        }
        self.watcher = watcher
        watcher.start()
    }

    /// First positional argument (skipping flags and the values of every value-taking flag); defaults to cwd.
    nonisolated static var initialRepoURL: URL {
        let args = CommandLine.arguments
        let valuedFlags: Set<String> = ["--shot", "--view", "--select", "--mode"]
        var positionals: [String] = []
        var i = 1
        while i < args.count {
            let a = args[i]
            if valuedFlags.contains(a) { i += 2; continue }   // skip flag AND its value
            if a.hasPrefix("--") { i += 1; continue }          // skip valueless flag (e.g. --dark)
            positionals.append(a); i += 1
        }
        let path = positionals.first ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: path)
    }
}

extension WorkbenchLayoutStore {
    /// Demo persistence backed by `UserDefaults.standard`, namespaced by key. Shows how a host wires
    /// storage into the component — the component itself never touches UserDefaults.
    static let userDefaults = WorkbenchLayoutStore(
        load: { key in
            (UserDefaults.standard.dictionary(forKey: "GitWorkbench.columns.\(key)") as? [String: Double])?
                .mapValues { CGFloat($0) }
        },
        save: { key, widths in
            UserDefaults.standard.set(widths.mapValues { Double($0) }, forKey: "GitWorkbench.columns.\(key)")
        }
    )
}

/// Roots the live view on `AppModel` so swapping the repository rebuilds the UI against the new store.
struct RootView: View {
    @ObservedObject var app: AppModel
    var body: some View {
        GitWorkbenchView(store: app.store)
            .frame(minWidth: 1080, minHeight: 660)
    }
}

@MainActor
final class LiveDemoDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// The AppKit-owned Theme submenu (see `installThemeMenu`). Held so `menuNeedsUpdate` can target it.
    private var themeMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--shot"), i + 1 < args.count {
            runSnapshot(path: args[i + 1],
                        view: arg(args, "--view"),
                        select: arg(args, "--select"),
                        mode: arg(args, "--mode"))
        } else {
            runWindowed()
        }
    }

    /// Interactive mode. The `WindowGroup` window is not reliably created for this executable target,
    /// so if none has appeared shortly after launch we host the view in an explicit window. Either way
    /// we kick off the initial load (the live store starts empty until `reload`).
    private func runWindowed() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if NSApp.windows.first(where: { $0.contentView != nil }) == nil {
                let size = NSRect(x: 0, y: 0, width: 1200, height: 740)
                let hosting = NSHostingView(rootView: RootView(app: .shared))
                hosting.frame = size
                let window = NSWindow(contentRect: size, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                      backing: .buffered, defer: false)
                window.title = "GitWorkbench (Live)"
                window.contentView = hosting
                window.center()
                window.makeKeyAndOrderFront(nil)
            } else {
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            installThemeMenu()
            await AppModel.shared.start()
        }
    }

    /// Build and install an AppKit "Theme" menu. The SwiftUI `.commands` menu can't drive the checkmark
    /// here: this executable's `WindowGroup` window never materializes (we host the view in an explicit
    /// `NSHostingView` window instead), so the command scene that owns the menu stays dormant and never
    /// re-evaluates when the theme changes — the mark froze on the launch-time theme. An AppKit menu whose
    /// `menuNeedsUpdate(_:)` reads the live `themeName` on every open sidesteps that dead scene.
    private func installThemeMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        // Idempotent: drop any prior Theme menu (ours, or a leftover SwiftUI one) before reinstalling.
        if let stale = mainMenu.items.first(where: { $0.title == "Theme" }) { mainMenu.removeItem(stale) }
        let menu = NSMenu(title: "Theme")
        menu.autoenablesItems = false
        menu.delegate = self
        for theme in DemoThemes.all {
            let item = NSMenuItem(title: theme.name, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let top = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        top.submenu = menu
        if let windowIndex = mainMenu.items.firstIndex(where: { $0.title == "Window" }) {
            mainMenu.insertItem(top, at: windowIndex)   // conventional slot: just before Window
        } else {
            mainMenu.addItem(top)
        }
        themeMenu = menu
    }

    /// Apply the picked theme. The checkmark follows on the menu's next open via `menuNeedsUpdate`.
    @objc private func selectTheme(_ sender: NSMenuItem) {
        AppModel.shared.applyTheme(named: sender.title)
    }

    /// Refresh the Theme menu's checkmarks from the live `themeName` each time it's about to open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === themeMenu else { return }
        let current = AppModel.shared.themeName
        for item in menu.items { item.state = (item.title == current) ? .on : .off }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func arg(_ args: [String], _ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Drives the store into the requested state, renders, captures the view to a PNG, and exits.
    ///
    /// `--shot` hosts the SwiftUI view in an explicit `NSWindow` (via `NSHostingView`) rather than
    /// relying on the `WindowGroup` window — that window is not reliably instantiated for this
    /// executable target, whereas an explicit window lays out and renders deterministically.
    private func runSnapshot(path: String, view: String?, select: String?, mode: String?) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon / minimal disturbance
        let dark = CommandLine.arguments.contains("--dark")
        let store = AppModel.shared.store
        let size = NSRect(x: 0, y: 0, width: 1200, height: 740)
        let hosting = NSHostingView(rootView: GitWorkbenchView(store: store).frame(width: size.width, height: size.height))
        hosting.frame = size
        let window = NSWindow(contentRect: size, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)

        Task { @MainActor in
            await store.reload()
            if let mode { store.setDiffMode(mode == "unified" ? .unified : .split) }
            switch view {
            case "history":
                store.select(.history)
                if let id = pick(store.state.commits.map(\.id), select) { await store.selectCommit(id) }
            case "stashes":
                store.select(.stashes)
                if let id = pick(store.state.stashes.map(\.id), select) { await store.selectStash(id) }
            default:
                store.select(.changes)
                if let f = store.state.repo.files.first(where: { $0.path == select }) ?? store.state.repo.files.first {
                    store.select(file: f.id)
                }
            }
            // Let the async diff load + SwiftUI layout settle, then capture the hosting view.
            try? await Task.sleep(for: .milliseconds(1600))
            capture(view: hosting, to: path)
            NSApp.terminate(nil)
        }
    }

    private func pick(_ ids: [String], _ select: String?) -> String? {
        if let select, ids.contains(select) { return select }
        return ids.first
    }

    private func capture(view: NSView, to path: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write(Data("SHOT-FAILED no bitmap\n".utf8)); return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            FileHandle.standardError.write(Data("SHOT \(path) \(Int(view.bounds.width))x\(Int(view.bounds.height))\n".utf8))
        }
    }
}

@main
struct GitWorkbenchLiveDemoApp: App {
    @NSApplicationDelegateAdaptor(LiveDemoDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("GitWorkbench (Live)") {
            RootView(app: .shared)
        }
        .defaultSize(width: 1200, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Repository\u{2026}") { AppModel.shared.openWithPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
