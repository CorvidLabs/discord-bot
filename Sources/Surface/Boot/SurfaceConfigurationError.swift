import Foundation

/// Why this process will not start.
///
/// Every case names the variable to change. `ADOPT-2` is that an operator
/// finds out they set it up wrong before their members do, and `RUN-9.a` is
/// that a version needing a setting refuses and names it rather than starting
/// and behaving differently. There is no case here that can be recovered from
/// by trying again, which is why none of them is an optional.
public enum SurfaceConfigurationError: Error, Equatable, LocalizedError, Sendable {

    /// A required variable is unset or blank.
    case missing(key: String, why: String)

    /// A variable still holds a value copied out of an example file.
    ///
    /// `ADOPT-7.a`: a placeholder somebody forgot to replace stops the boot
    /// rather than pointing the bot at a stranger's server.
    case placeholder(key: String, value: String)

    /// A variable holds something that is not the shape it must be.
    case invalid(key: String, value: String, why: String)

    // MARK: - Public Methods

    public var errorDescription: String? {
        switch self {
        case .missing(let key, let why):
            return "\(key) is required and is not set: \(why)."
        case .placeholder(let key, let value):
            return "\(key) still holds the example value '\(value)'. Replace it with yours. "
                + "Starting with a placeholder points this bot at somebody else's server."
        case .invalid(let key, let value, let why):
            return "\(key) is '\(value)', which will not do: \(why)."
        }
    }
}

/// Values that mean somebody copied the example file and did not finish.
///
/// A short list on purpose. A long one eventually refuses somebody's real
/// value, and a bot that will not start over a legitimate setting is worse
/// than one that starts with a bad one.
public enum PlaceholderValues: Sendable {

    // MARK: - Properties

    /// Exact values, compared without regard to case.
    public static let exact: Set<String> = [
        "changeme",
        "change-me",
        "your-token-here",
        "your-guild-id",
        "xxx",
        "todo",
        "replace-me",
        "0"
    ]

    // MARK: - Public Methods

    /// Whether this looks like something nobody meant to leave in.
    ///
    /// Anything in ``exact``, and anything wrapped in angle brackets, which is
    /// how every example file in this repository writes a blank to fill in.
    ///
    /// - Parameter value: The value as written.
    public static func looksUnfinished(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">") { return true }
        return exact.contains(trimmed)
    }
}
