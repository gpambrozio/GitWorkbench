import Foundation

public struct Toast: Identifiable, Sendable, Equatable {
    public enum Style: Sendable, Equatable { case success, info, error, progress }
    public var id: UUID
    public var message: String
    public var style: Style

    public init(id: UUID = UUID(), message: String, style: Style = .success) {
        self.id = id; self.message = message; self.style = style
    }

    public static func success(_ message: String) -> Toast { .init(message: message, style: .success) }
    public static func info(_ message: String) -> Toast { .init(message: message, style: .info) }
    public static func error(_ message: String) -> Toast { .init(message: message, style: .error) }
    public static func progress(_ message: String) -> Toast { .init(message: message, style: .progress) }
}
