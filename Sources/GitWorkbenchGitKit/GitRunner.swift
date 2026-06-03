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

        do { try process.run() }
        catch { throw GitError.gitNotFound(gitPath) }

        async let outData = Self.readToEnd(outPipe.fileHandleForReading)
        async let errData = Self.readToEnd(errPipe.fileHandleForReading)
        let (out, err) = await (outData, errData)
        process.waitUntilExit()

        return GitOutput(stdout: out,
                         stderr: String(decoding: err, as: UTF8.self),
                         exitCode: process.terminationStatus)
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
