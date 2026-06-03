import Foundation
import CoreServices

/// Watches a git working tree recursively (via FSEvents) and fires a debounced callback whenever
/// something changes on disk, so a host can call `store.reload()` to pick up edits, commits, branch
/// switches, or stashes made outside the app. Lives in GitKit, not the dependency-free core, because it
/// touches the filesystem directly.
///
/// The host must keep a strong reference for as long as it wants events (the FSEvents callback holds the
/// watcher unretained); drop it (or call `stop()`) to tear the stream down.
public final class RepositoryWatcher: @unchecked Sendable {
    private let path: String
    private let latency: CFTimeInterval
    private let debounce: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "dev.gitworkbench.RepositoryWatcher")
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    /// Directory names whose events are ignored — build output / package caches that `git status` ignores
    /// anyway, so they'd only trigger no-op reloads. `.git` is intentionally NOT here: its changes are how
    /// we detect external commits / branch switches / stashes.
    private static let ignoredDirs: Set<String> = [".build", "DerivedData", "node_modules", ".swiftpm"]

    public init(url: URL, debounce: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void) {
        // Resolve symlinks so this matches the realpaths FSEvents reports (e.g. /var → /private/var).
        self.path = url.resolvingSymlinksInPath().path
        self.latency = 0.15
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() { queue.async { [weak self] in self?.startOnQueue() } }
    public func stop() { queue.async { [weak self] in self?.stopOnQueue() } }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: - Queue-isolated

    private func startOnQueue() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes
                         | kFSEventStreamCreateFlagFileEvents
                         | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, paths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<RepositoryWatcher>.fromOpaque(info).takeUnretainedValue()
                let changed = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                watcher.handle(paths: changed)
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func stopOnQueue() {
        pending?.cancel()
        pending = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Runs on `queue`. Coalesces bursts into one callback after a quiet period.
    private func handle(paths: [String]) {
        guard Self.isRelevant(paths, root: path) else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    /// Whether a batch of changed paths warrants a reload. A path matters only if it is neither the bare
    /// watched root (FSEvents always reports it as a coarse "something under here changed" signal) nor
    /// inside an ignored build/cache dir. Pure + `static` so it can be unit-tested without FSEvents.
    static func isRelevant(_ paths: [String], root: String) -> Bool {
        paths.contains { changed in
            changed != root && Set((changed as NSString).pathComponents).isDisjoint(with: ignoredDirs)
        }
    }
}
