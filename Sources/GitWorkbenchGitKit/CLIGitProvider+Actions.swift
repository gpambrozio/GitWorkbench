import Foundation
import GitWorkbench

extension CLIGitProvider {
    public func stage(_ files: [FileChange]) async throws {
        guard !files.isEmpty else { return }
        _ = try await runner.output(["add", "--"] + uniquePaths(files))
    }

    public func unstage(_ files: [FileChange]) async throws {
        guard !files.isEmpty else { return }
        _ = try await runner.output(["restore", "--staged", "--"] + uniquePaths(files))
    }

    public func discard(_ file: FileChange) async throws {
        if file.status == .untracked {
            // Untracked files aren't in the index or HEAD, so `restore` can't match them.
            // `-d` so a fully-untracked directory (reported as a single entry) is removed too, not just files.
            _ = try await runner.output(["clean", "-fd", "--", file.path])
        } else {
            // Reset BOTH the index and the working tree to HEAD. The old `restore -- <path>` only reverted
            // the worktree from the index, so a STAGED modification (or staged deletion) survived in the
            // index and reappeared on the next status read. This form also removes a staged-added file,
            // whose path isn't in HEAD.
            _ = try await runner.output(["restore", "--source=HEAD", "--staged", "--worktree", "--", file.path])
        }
    }

    public func commit(message: String, staged: [FileChange]) async throws -> Commit {
        _ = try await runner.output(["commit", "-m", message])
        let out = try await runner.output(["log", "-1", "--format=\(Self.logFormat)"]).text
        guard var commit = LogParser.parse(out).first else {
            // The commit itself succeeded; only the read-back parse failed. Use -1 (not 0) so the
            // error doesn't claim a zero/success exit code.
            throw GitError.commandFailed(arguments: ["log", "-1"], code: -1, stderr: "could not read new commit")
        }
        commit.files = (try? await commitFiles(commit.id)) ?? staged
        if commit.relativeDate.isEmpty { commit.relativeDate = commit.date }
        return commit
    }

    public func pull() async throws -> SyncResult { try await sync(["pull"]) }
    public func push() async throws -> SyncResult { try await sync(["push"]) }
    public func fetch() async throws -> SyncResult { try await sync(["fetch"]) }

    public func switchBranch(to branch: Branch) async throws {
        _ = try await runner.output(["switch", branch.name])
    }

    public func checkoutRemoteBranch(_ branch: RemoteBranch) async throws {
        // If a local branch of this name already exists, switch to it; otherwise create a local
        // branch tracking the remote ref (`git switch --track origin/x` makes local `x` track it).
        // Checking first keeps the surfaced error the real one from the command we mean to run,
        // rather than a confusing "already exists" / "invalid reference" from a blind fallback.
        let exists = try await runner.run(["show-ref", "--verify", "--quiet", "refs/heads/\(branch.name)"])
        if exists.exitCode == 0 {
            _ = try await runner.output(["switch", branch.name])
        } else {
            _ = try await runner.output(["switch", "--track", branch.id])
        }
    }

    public func applyStash(_ stash: Stash) async throws { _ = try await runner.output(["stash", "apply", stash.ref]) }
    public func popStash(_ stash: Stash) async throws { _ = try await runner.output(["stash", "pop", stash.ref]) }
    public func dropStash(_ stash: Stash) async throws { _ = try await runner.output(["stash", "drop", stash.ref]) }

    public func checkout(_ commit: Commit) async throws {
        _ = try await runner.output(["checkout", commit.id])
    }

    public func resetHEAD(to commit: Commit, mode: ResetMode) async throws {
        _ = try await runner.output(["reset", "--\(mode.rawValue)", commit.id])
    }

    public func revert(_ commit: Commit) async throws {
        // `--no-edit` so the revert doesn't open `$EDITOR` and hang the headless process.
        _ = try await runner.output(["revert", "--no-edit", commit.id])
    }

    public func cherryPick(_ commit: Commit) async throws {
        _ = try await runner.output(["cherry-pick", commit.id])
    }

    public func createBranch(named name: String, at commit: Commit) async throws {
        // `git branch <name> <sha>` creates the ref without switching to it. The `--`
        // terminator (as in `stage`/`unstage`) stops a leading-dash name being parsed as an
        // option — e.g. a bare `-m` would otherwise rename the checked-out branch to the SHA.
        _ = try await runner.output(["branch", "--", name, commit.id])
    }

    public func createTag(named name: String, at commit: Commit) async throws {
        // `--` so a leading-dash name (e.g. `-d`) is taken as the tag name, not a git option.
        _ = try await runner.output(["tag", "--", name, commit.id])
    }

    private func uniquePaths(_ files: [FileChange]) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for f in files where seen.insert(f.path).inserted { result.append(f.path) }
        return result
    }

    private func sync(_ args: [String]) async throws -> SyncResult {
        let result = try await runner.run(args)
        guard result.exitCode == 0 else {
            throw GitError.commandFailed(arguments: args, code: result.exitCode, stderr: result.stderr)
        }
        let status = try await loadStatus()
        let raw = result.stderr.isEmpty ? result.text : result.stderr
        let line = raw.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces)
        return SyncResult(ahead: status.ahead, behind: status.behind,
                          message: (line?.isEmpty == false ? line! : "Up to date with origin"))
    }
}
