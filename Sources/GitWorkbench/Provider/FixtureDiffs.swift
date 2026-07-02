import Foundation

/// Diff content for the mock provider, mirroring reference/src/gitdata.js hunks.
/// Keyed by diff context + repo-relative path.
public enum FixtureDiffs {

    /// Resolve a diff for a file in a context, or nil if there is no fixture for it.
    public static func diff(for file: FileChange, context: DiffRequest.Context) -> FileDiff? {
        // Binary image/PDF fixtures (issue #12) live in the working tree. There's a single blob per
        // path — no separate staged version — so the same content resolves whether or not the file is
        // staged: staging a fixture in the demo must still show its image/PDF diff.
        if case .workingTree = context, let content = binaryContent[file.path] {
            return FileDiff(file: file, hunks: [], isBinary: true, binaryContent: content)
        }
        let hunks: [DiffHunk]?
        switch context {
        case .workingTree:
            hunks = workingTree[file.path]
        case .commit(let id):
            hunks = commitDiffs[id]?[file.path]
        case .stash(let id):
            hunks = stashDiffs[id]?[file.path]
        }
        guard let hunks else { return nil }
        return DiffBuilder.fileDiff(file, hunks: hunks)
    }

    // MARK: Binary content (image/PDF), keyed by working-tree path

    static let binaryContent: [String: BinaryContent] = [
        "assets/banner.png": BinaryContent(kind: .image, old: FixtureImages.bannerOld, new: FixtureImages.bannerNew),
        "assets/screenshot.png": BinaryContent(kind: .image, old: nil, new: FixtureImages.screenshotNew),
        "docs/spec.pdf": BinaryContent(kind: .pdf, old: FixtureImages.specOld, new: FixtureImages.specNew),
    ]

    // MARK: Working-tree diffs (by path) — ported from gitdata.js `files`

    static let workingTree: [String: [DiffHunk]] = [
        "src/commands/sync.ts": [
            DiffBuilder.hunk(oldStart: 14, newStart: 14, [
                " import { Logger } from \"../utils/logger\";",
                " import { loadConfig } from \"../config\";",
                "-import { sleep } from \"../utils/time\";",
                "+import { sleep, jitter } from \"../utils/time\";",
                " ",
                " const MAX_RETRIES = 5;",
                "+const BASE_DELAY_MS = 250;",
                " ",
                " export async function sync(opts: SyncOptions) {",
                "   const cfg = await loadConfig(opts.cwd);",
            ]),
            DiffBuilder.hunk(oldStart: 41, newStart: 42, [
                "   const remote = cfg.remotes[opts.remote ?? \"origin\"];",
                "-  if (!remote) throw new Error(\"unknown remote\");",
                "+  if (!remote) {",
                "+    log.error(`No remote named \"${opts.remote}\"`);",
                "+    throw new SyncError(\"UNKNOWN_REMOTE\", opts.remote);",
                "+  }",
                " ",
                "-  for (let i = 0; i < MAX_RETRIES; i++) {",
                "-    try {",
                "-      return await push(remote, opts.branch);",
                "-    } catch (e) {",
                "-      await sleep(1000);",
                "+  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {",
                "+    try {",
                "+      return await push(remote, opts.branch);",
                "+    } catch (err) {",
                "+      if (!isRetryable(err)) throw err;",
                "+      const delay = BASE_DELAY_MS * 2 ** attempt + jitter(100);",
                "+      log.warn(`push failed (attempt ${attempt}), retrying in ${delay}ms`);",
                "+      await sleep(delay);",
                "     }",
                "   }",
                "+  throw new SyncError(\"EXHAUSTED\", remote.url);",
                " }",
            ]),
        ],
        "src/index.ts": [
            DiffBuilder.hunk(oldStart: 3, newStart: 3, [
                " import { sync } from \"./commands/sync\";",
                " import { status } from \"./commands/status\";",
                "+import { watch } from \"./commands/watch\";",
                " ",
                " const cli = createCli({",
                "   name: \"aurora\",",
                "-  version: \"0.4.1\",",
                "+  version: \"0.5.0\",",
                " });",
                " ",
                " cli.register(sync);",
                "+cli.register(watch);",
            ]),
        ],
        "src/utils/logger.ts": [
            DiffBuilder.hunk(oldStart: 0, newStart: 1, [
                "+import { stderr } from \"node:process\";",
                "+",
                "+type Level = \"debug\" | \"info\" | \"warn\" | \"error\";",
                "+",
                "+const COLORS: Record<Level, string> = {",
                "+  debug: \"\\x1b[90m\",",
                "+  info: \"\\x1b[36m\",",
                "+  warn: \"\\x1b[33m\",",
                "+  error: \"\\x1b[31m\",",
                "+};",
                "+",
                "+export class Logger {",
                "+  constructor(private scope: string) {}",
                "+  private emit(level: Level, msg: string) {",
                "+    const tag = COLORS[level] + level.toUpperCase() + \"\\x1b[0m\";",
                "+    stderr.write(`${tag} [${this.scope}] ${msg}\\n`);",
                "+  }",
                "+  debug = (m: string) => this.emit(\"debug\", m);",
                "+  info = (m: string) => this.emit(\"info\", m);",
                "+  warn = (m: string) => this.emit(\"warn\", m);",
                "+  error = (m: string) => this.emit(\"error\", m);",
                "+}",
            ]),
        ],
        "package.json": [
            DiffBuilder.hunk(oldStart: 2, newStart: 2, [
                "   \"name\": \"aurora-cli\",",
                "-  \"version\": \"0.4.1\",",
                "+  \"version\": \"0.5.0\",",
                "   \"type\": \"module\",",
                "   \"scripts\": {",
                "+    \"watch\": \"tsx src/index.ts watch\",",
                "+    \"lint\": \"eslint src --max-warnings 0\",",
                "     \"build\": \"tsup src/index.ts\"",
            ]),
        ],
        "README.md": [
            DiffBuilder.hunk(oldStart: 18, newStart: 18, [
                " ## Commands",
                " ",
                " - `aurora sync` — push local commits with retry + backoff",
                "+- `aurora watch` — re-sync automatically on file changes",
                " - `aurora status` — show working-tree changes",
                "+",
                "+## Configuration",
                "+",
                "+Set `AURORA_REMOTE` to override the default remote.",
            ]),
        ],
        "src/legacy/poller.ts": [
            DiffBuilder.hunk(oldStart: 1, newStart: 0, [
                "-// Deprecated: replaced by the fs.watch-based watcher in watch.ts",
                "-import { sleep } from \"../utils/time\";",
                "-",
                "-export async function poll(fn: () => void, ms: number) {",
                "-  while (true) {",
                "-    fn();",
                "-    await sleep(ms);",
                "-  }",
                "-}",
            ]),
        ],
        ".env.example": [
            DiffBuilder.hunk(oldStart: 0, newStart: 1, [
                "+AURORA_REMOTE=origin",
                "+AURORA_LOG_LEVEL=info",
                "+AURORA_TOKEN=",
                "+AURORA_MAX_RETRIES=5",
            ]),
        ],
    ]

    // MARK: Commit diffs (by commit id, then path) — ported from gitdata.js `commits[*].files`

    static let commitDiffs: [String: [String: [DiffHunk]]] = [
        // commit 9f2c1a4e7b3 — "Add structured Logger with level colors"
        "9f2c1a4e7b3": [
            "src/utils/logger.ts": [DiffBuilder.hunk(oldStart: 0, newStart: 1, [
                "+type Level = \"debug\" | \"info\" | \"warn\" | \"error\";",
                "+export class Logger {",
                "+  constructor(private scope: string) {}",
                "+  info = (m: string) => this.emit(\"info\", m);",
                "+}",
            ])],
            "src/commands/sync.ts": [DiffBuilder.hunk(oldStart: 11, newStart: 11, [
                " import { loadConfig } from \"../config\";",
                "+import { Logger } from \"../utils/logger\";",
                " ",
                "-const log = console;",
                "+const log = new Logger(\"sync\");",
                " ",
            ])],
        ],
        // commit 3b8e7d2f1a9 — "Switch watcher to fs.watch, drop poller"
        "3b8e7d2f1a9": [
            "src/commands/watch.ts": [DiffBuilder.hunk(oldStart: 0, newStart: 1, [
                "+import { watch } from \"node:fs\";",
                "+export async function watch(opts: WatchOptions) {",
                "+  watch(opts.cwd, { recursive: true }, debounce(onChange, 150));",
                "+}",
            ])],
            "src/legacy/poller.ts": [DiffBuilder.hunk(oldStart: 1, newStart: 0, [
                "-export async function poll(fn, ms) {",
                "-  while (true) { fn(); await sleep(ms); }",
                "-}",
            ])],
        ],
        // commit a17f9c0b5e2 — "Bump CLI to 0.5.0-rc.1"
        "a17f9c0b5e2": [
            "package.json": [DiffBuilder.hunk(oldStart: 2, newStart: 2, [
                "   \"name\": \"aurora-cli\",",
                "-  \"version\": \"0.4.1\",",
                "+  \"version\": \"0.5.0-rc.1\",",
                "   \"type\": \"module\",",
            ])],
        ],
        // commit e4d5b61c8d4 — "Format `status` command output as a table"
        "e4d5b61c8d4": [
            "src/commands/status.ts": [DiffBuilder.hunk(oldStart: 20, newStart: 20, [
                "   for (const f of files) {",
                "-    print(`${f.status} ${f.path}`);",
                "+    rows.push([glyph(f.status), f.path, stat(f)]);",
                "   }",
                "+  printTable(rows, { align: [\"center\", \"left\", \"right\"] });",
            ])],
        ],
        // commit 77ac3f9d2b6 — "Scaffold sync retry loop"
        "77ac3f9d2b6": [
            "src/commands/sync.ts": [DiffBuilder.hunk(oldStart: 0, newStart: 1, [
                "+export async function sync(opts: SyncOptions) {",
                "+  for (let i = 0; i < 5; i++) {",
                "+    try { return await push(opts); } catch { await sleep(1000); }",
                "+  }",
                "+}",
            ])],
        ],
        // commit 1c0aa28f0c1 — "chore: project scaffolding"
        "1c0aa28f0c1": [
            "package.json": [DiffBuilder.hunk(oldStart: 0, newStart: 1, [
                "+{",
                "+  \"name\": \"aurora-cli\",",
                "+  \"version\": \"0.4.0\"",
                "+}",
            ])],
        ],
    ]

    // MARK: Stash diffs (by stash id, then path) — ported from gitdata.js `stashes[*].files`

    static let stashDiffs: [String: [String: [DiffHunk]]] = [
        // stash0 — "WIP: tune retry delays"
        "stash0": [
            "src/commands/sync.ts": [DiffBuilder.hunk(oldStart: 38, newStart: 38, [
                "   for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {",
                "-      const delay = BASE_DELAY_MS * 2 ** attempt;",
                "+      const delay = Math.min(BASE_DELAY_MS * 2 ** attempt, 8000);",
                "+      const wobble = jitter(delay * 0.2);",
                "-      await sleep(delay);",
                "+      await sleep(delay + wobble);",
                "   }",
            ])],
        ],
        // stash1 — "experiment: parallel push to mirrors"
        "stash1": [
            "src/commands/sync.ts": [DiffBuilder.hunk(oldStart: 44, newStart: 44, [
                "-  return await push(remote, opts.branch);",
                "+  const mirrors = cfg.mirrors ?? [];",
                "+  await Promise.all([",
                "+    push(remote, opts.branch),",
                "+    ...mirrors.map((m) => push(m, opts.branch)),",
                "+  ]);",
            ])],
            "src/config.ts": [DiffBuilder.hunk(oldStart: 8, newStart: 8, [
                "   remotes: Record<string, Remote>;",
                "+  mirrors?: Remote[];",
            ])],
        ],
    ]
}
