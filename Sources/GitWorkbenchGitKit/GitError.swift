import Foundation

/// Errors from running git.
public enum GitError: Error, LocalizedError, Equatable {
    case gitNotFound(String)
    case notARepository(String)
    case commandFailed(arguments: [String], code: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .gitNotFound(let path):
            return "git executable not found at \(path)."
        case .notARepository(let path):
            return "\(path) is not a git repository."
        case .commandFailed(_, _, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().contains("rejected") || trimmed.lowercased().contains("non-fast-forward") {
                return "Push rejected \u{2014} pull first"
            }
            return trimmed.isEmpty ? "git command failed." : trimmed
        }
    }
}
