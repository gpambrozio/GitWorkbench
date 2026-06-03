import SwiftUI
import AppKit
import GitWorkbench

/// Shared store so the App scene and the launch delegate (snapshot mode) use the same instance.
@MainActor
enum DemoState {
    static let store = GitWorkbenchStore.preview
}

@MainActor
final class DemoAppDelegate: NSObject, NSApplicationDelegate {
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
        let store = DemoState.store
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
            // Let async diff loads + SwiftUI layout settle before capturing.
            try? await Task.sleep(for: .milliseconds(1300))
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
struct GitWorkbenchDemoApp: App {
    @NSApplicationDelegateAdaptor(DemoAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("GitWorkbench Demo") {
            GitWorkbenchView(store: DemoState.store)
                .frame(minWidth: 1080, minHeight: 660)
        }
        .defaultSize(width: 1200, height: 740)
    }
}
