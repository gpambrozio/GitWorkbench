import SwiftUI
import AppKit
import GitWorkbench
import GitWorkbenchGitKit

/// Shared store so the App scene and the launch delegate (snapshot mode) use the same instance.
/// Unlike the mock demo, this is backed by a real `CLIGitProvider` pointed at a repo on disk.
@MainActor
enum LiveState {
    static let store = GitWorkbenchStore(provider: CLIGitProvider(repositoryURL: repoURL))

    /// First positional argument (skipping flags and the values of `--shot`/`--view`); defaults to cwd.
    static let repoURL: URL = {
        let args = CommandLine.arguments
        let valuedFlags: Set<String> = ["--shot", "--view"]
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
    }()
}

@MainActor
final class LiveDemoDelegate: NSObject, NSApplicationDelegate {
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
                let hosting = NSHostingView(rootView: GitWorkbenchView(store: LiveState.store)
                    .frame(minWidth: size.width, minHeight: size.height))
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
            await LiveState.store.reload()
        }
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
        let store = LiveState.store
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
            GitWorkbenchView(store: LiveState.store)
                .frame(minWidth: 1080, minHeight: 660)
        }
        .defaultSize(width: 1200, height: 740)
    }
}
