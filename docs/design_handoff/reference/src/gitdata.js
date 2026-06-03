// gitdata.js — realistic mock repository state for the git-changes viewer.
// Exposes window.GITDATA = { repo, branch, ahead, behind, files }
// Each file: { id, path, dir, name, status, staged, add, del, lang, hunks?, note? }
// Each hunk: { header, lines: [{ t:'ctx'|'add'|'del', o:oldNo|null, n:newNo|null, text }] }
(function () {
  // Build structured hunk lines from a compact patch (lines prefixed +/-/space).
  function hunk(oldStart, newStart, raw) {
    let o = oldStart, n = newStart;
    const lines = raw.map((L) => {
      const t = L[0] === '+' ? 'add' : L[0] === '-' ? 'del' : 'ctx';
      const text = L.slice(1);
      const row = { t, text, o: null, n: null };
      if (t === 'ctx') { row.o = o++; row.n = n++; }
      else if (t === 'add') { row.n = n++; }
      else { row.o = o++; }
      return row;
    });
    const header = `@@ -${oldStart},${lines.filter((l) => l.t !== 'add').length} +${newStart},${lines.filter((l) => l.t !== 'del').length} @@`;
    return { header, lines };
  }

  const files = [
    {
      id: 'sync', path: 'src/commands/sync.ts', dir: 'src/commands', name: 'sync.ts',
      status: 'M', staged: true, add: 24, del: 6, lang: 'ts',
      hunks: [
        hunk(14, 14, [
          ' import { Logger } from "../utils/logger";',
          ' import { loadConfig } from "../config";',
          '-import { sleep } from "../utils/time";',
          '+import { sleep, jitter } from "../utils/time";',
          ' ',
          ' const MAX_RETRIES = 5;',
          '+const BASE_DELAY_MS = 250;',
          ' ',
          ' export async function sync(opts: SyncOptions) {',
          '   const cfg = await loadConfig(opts.cwd);',
        ]),
        hunk(41, 42, [
          '   const remote = cfg.remotes[opts.remote ?? "origin"];',
          '-  if (!remote) throw new Error("unknown remote");',
          '+  if (!remote) {',
          '+    log.error(`No remote named "${opts.remote}"`);',
          '+    throw new SyncError("UNKNOWN_REMOTE", opts.remote);',
          '+  }',
          ' ',
          '-  for (let i = 0; i < MAX_RETRIES; i++) {',
          '-    try {',
          '-      return await push(remote, opts.branch);',
          '-    } catch (e) {',
          '-      await sleep(1000);',
          '+  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {',
          '+    try {',
          '+      return await push(remote, opts.branch);',
          '+    } catch (err) {',
          '+      if (!isRetryable(err)) throw err;',
          '+      const delay = BASE_DELAY_MS * 2 ** attempt + jitter(100);',
          '+      log.warn(`push failed (attempt ${attempt}), retrying in ${delay}ms`);',
          '+      await sleep(delay);',
          '     }',
          '   }',
          '+  throw new SyncError("EXHAUSTED", remote.url);',
          ' }',
        ]),
      ],
    },
    {
      id: 'index', path: 'src/index.ts', dir: 'src', name: 'index.ts',
      status: 'M', staged: true, add: 8, del: 2, lang: 'ts',
      hunks: [
        hunk(3, 3, [
          ' import { sync } from "./commands/sync";',
          ' import { status } from "./commands/status";',
          '+import { watch } from "./commands/watch";',
          ' ',
          ' const cli = createCli({',
          '   name: "aurora",',
          '-  version: "0.4.1",',
          '+  version: "0.5.0",',
          ' });',
          ' ',
          ' cli.register(sync);',
          '+cli.register(watch);',
        ]),
      ],
    },
    {
      id: 'logger', path: 'src/utils/logger.ts', dir: 'src/utils', name: 'logger.ts',
      status: 'A', staged: true, add: 31, del: 0, lang: 'ts',
      hunks: [
        hunk(0, 1, [
          '+import { stderr } from "node:process";',
          '+',
          '+type Level = "debug" | "info" | "warn" | "error";',
          '+',
          '+const COLORS: Record<Level, string> = {',
          '+  debug: "\\x1b[90m",',
          '+  info: "\\x1b[36m",',
          '+  warn: "\\x1b[33m",',
          '+  error: "\\x1b[31m",',
          '+};',
          '+',
          '+export class Logger {',
          '+  constructor(private scope: string) {}',
          '+  private emit(level: Level, msg: string) {',
          '+    const tag = COLORS[level] + level.toUpperCase() + "\\x1b[0m";',
          '+    stderr.write(`${tag} [${this.scope}] ${msg}\\n`);',
          '+  }',
          '+  debug = (m: string) => this.emit("debug", m);',
          '+  info = (m: string) => this.emit("info", m);',
          '+  warn = (m: string) => this.emit("warn", m);',
          '+  error = (m: string) => this.emit("error", m);',
          '+}',
        ]),
      ],
    },
    {
      id: 'pkg', path: 'package.json', dir: '', name: 'package.json',
      status: 'M', staged: false, add: 3, del: 1, lang: 'json',
      hunks: [
        hunk(2, 2, [
          '   "name": "aurora-cli",',
          '-  "version": "0.4.1",',
          '+  "version": "0.5.0",',
          '   "type": "module",',
          '   "scripts": {',
          '+    "watch": "tsx src/index.ts watch",',
          '+    "lint": "eslint src --max-warnings 0",',
          '     "build": "tsup src/index.ts"',
        ]),
      ],
    },
    {
      id: 'readme', path: 'README.md', dir: '', name: 'README.md',
      status: 'M', staged: false, add: 5, del: 0, lang: 'md',
      hunks: [
        hunk(18, 18, [
          ' ## Commands',
          ' ',
          ' - `aurora sync` — push local commits with retry + backoff',
          '+- `aurora watch` — re-sync automatically on file changes',
          ' - `aurora status` — show working-tree changes',
          '+',
          '+## Configuration',
          '+',
          '+Set `AURORA_REMOTE` to override the default remote.',
        ]),
      ],
    },
    {
      id: 'poller', path: 'src/legacy/poller.ts', dir: 'src/legacy', name: 'poller.ts',
      status: 'D', staged: false, add: 0, del: 18, lang: 'ts',
      hunks: [
        hunk(1, 0, [
          '-// Deprecated: replaced by the fs.watch-based watcher in watch.ts',
          '-import { sleep } from "../utils/time";',
          '-',
          '-export async function poll(fn: () => void, ms: number) {',
          '-  while (true) {',
          '-    fn();',
          '-    await sleep(ms);',
          '-  }',
          '-}',
        ]),
      ],
    },
    {
      id: 'env', path: '.env.example', dir: '', name: '.env.example',
      status: 'U', staged: false, add: 4, del: 0, lang: 'env',
      hunks: [
        hunk(0, 1, [
          '+AURORA_REMOTE=origin',
          '+AURORA_LOG_LEVEL=info',
          '+AURORA_TOKEN=',
          '+AURORA_MAX_RETRIES=5',
        ]),
      ],
    },
  ];

  // ── commit history (newest first) ─────────────────────────
  function cf(path, status, add, del, hunks) {
    const i = path.lastIndexOf('/');
    return { id: path, path, dir: i < 0 ? '' : path.slice(0, i), name: i < 0 ? path : path.slice(i + 1), status, add, del, hunks };
  }

  const commits = [
    {
      sha: '9f2c1a4e7b3', short: '9f2c1a4', summary: 'Add structured Logger with level colors',
      body: 'Replaces scattered console.log calls with a scoped Logger that writes\nleveled, colorized output to stderr. Wires it through the sync command.',
      author: 'Gustavo', initials: 'GA', email: 'gustavo@aurora.dev',
      date: 'Today, 09:42', relative: '3 hours ago', tags: ['HEAD', 'feat/auto-sync'], parents: ['3b8e7d2'],
      files: [
        cf('src/utils/logger.ts', 'A', 31, 0, [hunk(0, 1, [
          '+type Level = "debug" | "info" | "warn" | "error";',
          '+export class Logger {',
          '+  constructor(private scope: string) {}',
          '+  info = (m: string) => this.emit("info", m);',
          '+}',
        ])]),
        cf('src/commands/sync.ts', 'M', 4, 1, [hunk(11, 11, [
          ' import { loadConfig } from "../config";',
          '+import { Logger } from "../utils/logger";',
          ' ',
          '-const log = console;',
          '+const log = new Logger("sync");',
          ' ',
        ])]),
      ],
    },
    {
      sha: '3b8e7d2f1a9', short: '3b8e7d2', summary: 'Switch watcher to fs.watch, drop poller',
      body: 'The legacy interval poller is replaced by an fs.watch-based watcher\nfor lower latency and CPU. Removes src/legacy/poller.ts.',
      author: 'Gustavo', initials: 'GA', email: 'gustavo@aurora.dev',
      date: 'Yesterday, 18:20', relative: '1 day ago', tags: [], parents: ['a17f9c0'],
      files: [
        cf('src/commands/watch.ts', 'A', 22, 0, [hunk(0, 1, [
          '+import { watch } from "node:fs";',
          '+export async function watch(opts: WatchOptions) {',
          '+  watch(opts.cwd, { recursive: true }, debounce(onChange, 150));',
          '+}',
        ])]),
        cf('src/legacy/poller.ts', 'D', 0, 9, [hunk(1, 0, [
          '-export async function poll(fn, ms) {',
          '-  while (true) { fn(); await sleep(ms); }',
          '-}',
        ])]),
      ],
    },
    {
      sha: 'a17f9c0b5e2', short: 'a17f9c0', summary: 'Bump CLI to 0.5.0-rc.1',
      body: 'Pre-release cut for the auto-sync feature branch.',
      author: 'Mira Patel', initials: 'MP', email: 'mira@aurora.dev',
      date: 'Mon, 14:05', relative: '3 days ago', tags: ['v0.5.0-rc.1'], parents: ['e4d5b61'],
      files: [
        cf('package.json', 'M', 1, 1, [hunk(2, 2, [
          '   "name": "aurora-cli",',
          '-  "version": "0.4.1",',
          '+  "version": "0.5.0-rc.1",',
          '   "type": "module",',
        ])]),
      ],
    },
    {
      sha: 'e4d5b61c8d4', short: 'e4d5b61', summary: 'Format `status` command output as a table',
      body: 'Aligns the working-tree status output into columns with status glyphs.',
      author: 'Mira Patel', initials: 'MP', email: 'mira@aurora.dev',
      date: 'Mon, 11:32', relative: '3 days ago', tags: [], parents: ['77ac3f9'],
      files: [
        cf('src/commands/status.ts', 'M', 14, 6, [hunk(20, 20, [
          '   for (const f of files) {',
          '-    print(`${f.status} ${f.path}`);',
          '+    rows.push([glyph(f.status), f.path, stat(f)]);',
          '   }',
          '+  printTable(rows, { align: ["center", "left", "right"] });',
        ])]),
      ],
    },
    {
      sha: '77ac3f9d2b6', short: '77ac3f9', summary: 'Scaffold sync retry loop',
      body: 'First pass at the push retry loop (fixed delay; backoff comes later).',
      author: 'Gustavo', initials: 'GA', email: 'gustavo@aurora.dev',
      date: 'Sun, 22:14', relative: '4 days ago', tags: [], parents: ['1c0aa28'],
      files: [
        cf('src/commands/sync.ts', 'A', 18, 0, [hunk(0, 1, [
          '+export async function sync(opts: SyncOptions) {',
          '+  for (let i = 0; i < 5; i++) {',
          '+    try { return await push(opts); } catch { await sleep(1000); }',
          '+  }',
          '+}',
        ])]),
      ],
    },
    {
      sha: '1c0aa28f0c1', short: '1c0aa28', summary: 'chore: project scaffolding',
      body: 'Initial TypeScript + tsup setup.',
      author: 'Mira Patel', initials: 'MP', email: 'mira@aurora.dev',
      date: 'Sat, 10:00', relative: '5 days ago', tags: ['main'], parents: [],
      files: [
        cf('package.json', 'A', 12, 0, [hunk(0, 1, [
          '+{',
          '+  "name": "aurora-cli",',
          '+  "version": "0.4.0"',
          '+}',
        ])]),
      ],
    },
  ];

  // ── stash entries ─────────────────────────────────────────
  const stashes = [
    {
      id: 'stash0', ref: 'stash@{0}', message: 'WIP: tune retry delays',
      branch: 'feat/auto-sync', relative: '40 minutes ago', date: 'Today, 12:05',
      files: [
        cf('src/commands/sync.ts', 'M', 3, 2, [hunk(38, 38, [
          '   for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {',
          '-      const delay = BASE_DELAY_MS * 2 ** attempt;',
          '+      const delay = Math.min(BASE_DELAY_MS * 2 ** attempt, 8000);',
          '+      const wobble = jitter(delay * 0.2);',
          '-      await sleep(delay);',
          '+      await sleep(delay + wobble);',
          '   }',
        ])]),
      ],
    },
    {
      id: 'stash1', ref: 'stash@{1}', message: 'experiment: parallel push to mirrors',
      branch: 'feat/auto-sync', relative: '2 days ago', date: 'Sun, 19:48',
      files: [
        cf('src/commands/sync.ts', 'M', 6, 1, [hunk(44, 44, [
          '-  return await push(remote, opts.branch);',
          '+  const mirrors = cfg.mirrors ?? [];',
          '+  await Promise.all([',
          '+    push(remote, opts.branch),',
          '+    ...mirrors.map((m) => push(m, opts.branch)),',
          '+  ]);',
        ])]),
        cf('src/config.ts', 'M', 2, 0, [hunk(8, 8, [
          '   remotes: Record<string, Remote>;',
          '+  mirrors?: Remote[];',
        ])]),
      ],
    },
  ];

  window.GITDATA = {
    repo: 'aurora-cli',
    branch: 'feat/auto-sync',
    upstream: 'origin/feat/auto-sync',
    ahead: 2,
    behind: 1,
    author: { name: 'Gustavo', initials: 'GA' },
    files,
    commits,
    stashes,
    get staged() { return files.filter((f) => f.staged); },
    get unstaged() { return files.filter((f) => !f.staged); },
    statusLabel: { M: 'Modified', A: 'Added', D: 'Deleted', R: 'Renamed', U: 'Untracked' },
  };
})();
