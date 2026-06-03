import Foundation

/// The result of a git invocation.
public struct GitOutput: Sendable {
    public var stdout: Data
    public var stderr: String
    public var exitCode: Int32
    public var text: String { String(decoding: stdout, as: UTF8.self) }
}

/// Runs `git` in a repository directory via Foundation `Process`. Drains stdout/stderr
/// concurrently (no pipe-buffer deadlock). `Sendable`: holds only immutable config.
public struct GitRunner: Sendable {
    public let repositoryURL: URL
    public let gitPath: String

    public init(repositoryURL: URL, gitPath: String = "/usr/bin/git") {
        self.repositoryURL = repositoryURL
        self.gitPath = gitPath
    }

    /// Runs git with the given arguments and returns the raw output (any exit code).
    public func run(_ arguments: [String]) async throws -> GitOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["-C", repositoryURL.path] + arguments
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice   // non-interactive: never block reading stdin

        // Drain stdout/stderr concurrently so a child that emits more than the pipe-buffer
        // size can't block on write — if it did, it would never terminate.
        async let outData = Self.readToEnd(outPipe.fileHandleForReading)
        async let errData = Self.readToEnd(errPipe.fileHandleForReading)

        // Wait for exit via `terminationHandler`, NOT `waitUntilExit()`. The latter spins a
        // CFRunLoop on the calling thread; on Swift's cooperative executor that intermittently
        // deadlocks (the child-termination wakeup is never serviced). The handler is installed
        // before `run()` so a fast-exiting child can't terminate before we're listening.
        do {
            let code: Int32 = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do { try process.run() }
                catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: GitError.gitNotFound(gitPath))
                }
            }
            let (out, err) = await (outData, errData)
            return GitOutput(stdout: out, stderr: String(decoding: err, as: UTF8.self), exitCode: code)
        } catch {
            // `run()` failed: the child never started, so close the write ends to give the
            // drain tasks EOF, then await them so no reader thread leaks. Rethrow the error.
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()
            _ = await (outData, errData)
            throw error
        }
    }

    /// Runs git and throws `GitError.commandFailed` on a non-zero exit; otherwise returns the output.
    public func output(_ arguments: [String]) async throws -> GitOutput {
        let result = try await run(arguments)
        guard result.exitCode == 0 else {
            throw GitError.commandFailed(arguments: arguments, code: result.exitCode, stderr: result.stderr)
        }
        return result
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = handle.readDataToEndOfFile()
                continuation.resume(returning: data)
            }
        }
    }
}
