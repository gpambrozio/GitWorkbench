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
            // `-d` so a fully-untracked directory (reported as a single entry) is removed too, not just files.
            _ = try await runner.output(["clean", "-fd", "--", file.path])
        } else {
            _ = try await runner.output(["restore", "--", file.path])
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

    public func applyStash(_ stash: Stash) async throws { _ = try await runner.output(["stash", "apply", stash.ref]) }
    public func popStash(_ stash: Stash) async throws { _ = try await runner.output(["stash", "pop", stash.ref]) }
    public func dropStash(_ stash: Stash) async throws { _ = try await runner.output(["stash", "drop", stash.ref]) }

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
