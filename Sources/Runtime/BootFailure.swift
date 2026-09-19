import Chain
import Foundation
import Gating

/// Why the process is stopping, in the shape the person who has to fix it
/// needs.
///
/// A value rather than a thrown module error, because what reaches the
/// operator has to carry three things at once: the variable to change, a
/// sentence saying what it is for, and the code the supervisor reads. Every
/// loader in the package already names its variable
/// (``Gating/GatingConfigurationError/missing(key:purpose:)``); this type is
/// how that survives the trip out through a process exit instead of being
/// flattened into "failed to load configuration", which is what the bot this
/// was ported from printed (ADOPT-2, RUN-9.a).
public struct BootFailure: Error, Sendable, Equatable {

    // MARK: - Properties

    /// The variable to change, when one variable is to blame.
    ///
    /// Nil for a refusal no single variable causes, such as a store another
    /// process is holding.
    public let variable: String?

    /// What is wrong, in one sentence, ending in a full stop.
    public let summary: String

    /// What to do about it, or nil when ``summary`` already says.
    public let remedy: String?

    /// What the process exits with.
    public let code: ExitCode

    // MARK: - Initializers

    /// - Parameters:
    ///   - variable: The variable to change, when one is to blame.
    ///   - summary: What is wrong.
    ///   - remedy: What to do about it.
    ///   - code: What the process exits with.
    public init(variable: String? = nil, summary: String, remedy: String? = nil, code: ExitCode) {
        self.variable = variable
        self.summary = summary
        self.remedy = remedy
        self.code = code
    }

    // MARK: - Public Methods

    /// The command that lists every variable this build reads.
    ///
    /// Named in a refusal that blames one variable, because the refusal can
    /// only report the **first** thing wrong: the loaders throw on the first
    /// bad value, so an operator who fixes it and starts again may be told
    /// about a second. The listing is what turns that into one round trip
    /// rather than four (RT-009, RUN-9).
    public static let listingCommand = "bot check"

    /// The refusal as the lines that go to standard error.
    ///
    /// The variable comes first on its own line, because it is the one thing
    /// somebody scanning a container log is looking for.
    public var lines: [String] {
        var out: [String] = []
        if let variable {
            out.append("refused: \(variable)")
        } else {
            out.append("refused")
        }
        out.append("  \(summary)")
        if let remedy {
            out.append("  \(remedy)")
        }
        if variable != nil {
            out.append(
                "  `\(Self.listingCommand)` lists every variable this build reads, marked set "
                    + "or unset, and what it made of yours."
            )
        }
        return out
    }
}

extension BootFailure {

    // MARK: - From the module errors

    /// A configuration refusal from one of the loaders, keeping the variable
    /// it named.
    ///
    /// The loaders throw typed errors that already carry the variable, so the
    /// only work here is pulling it back out. A `default` that dropped the
    /// variable would be the whole of ADOPT-2 lost in one line, so every case
    /// that carries one is matched.
    public static func configuration(_ error: any Error) -> BootFailure {
        if let gating = error as? GatingConfigurationError {
            return BootFailure(
                variable: gating.variableName,
                summary: gating.errorDescription ?? String(describing: gating),
                code: .configuration
            )
        }
        if let chain = error as? ChainConfigurationError {
            return BootFailure(
                variable: chain.variableName,
                summary: chain.errorDescription ?? String(describing: chain),
                code: .configuration
            )
        }
        if let failure = error as? BootFailure {
            return failure
        }
        return BootFailure(
            summary: (error as? any LocalizedError)?.errorDescription ?? "\(error)",
            code: .configuration
        )
    }
}
