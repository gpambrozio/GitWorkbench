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
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func arg(_ args: [String], _ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Drives the store into the requested state, renders, captures the window content to a PNG, and exits.
    private func runSnapshot(path: String, view: String?, select: String?, mode: String?) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon / minimal disturbance
        let dark = CommandLine.arguments.contains("--dark")
        let store = LiveState.store
        Task { @MainActor in
            NSApp.windows.first?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
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
            // Let async diff loads + SwiftUI layout settle before capturing. Real git is slower than
            // the mock provider, so allow a little more time than DemoApp.
            try? await Task.sleep(for: .milliseconds(1500))
            capture(to: path)
            NSApp.terminate(nil)
        }
    }

    private func pick(_ ids: [String], _ select: String?) -> String? {
        if let select, ids.contains(select) { return select }
        return ids.first
    }

    private func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write(Data("SHOT-FAILED no window\n".utf8)); return
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
