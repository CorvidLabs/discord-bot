import Foundation

/// A fact this layer was either told, or was not told.
///
/// The distinction is the entire reason the type exists. "This member holds
/// nothing" and "nobody could read what this member holds" lead to opposite
/// decisions: the first takes a role away, the second must leave every role
/// exactly where it is. An `Optional` collapses the two the moment somebody
/// writes `?? 0`, and somebody always writes `?? 0`.
///
/// The original had this as a bare `Bool?` in one place, a cached balance
/// standing in silently in another, and nothing at all in a third. The third
/// was the expensive one: a transient provider error read a liquidity position
/// as zero, which read as a sold-up member, which stripped roles from somebody
/// who had done nothing. Roles came back on the next sweep, which is not the
/// same as never having lost them.
///
/// So there is deliberately no accessor that hands back a value with a
/// default. A caller either switches on the case or calls ``require(_:)`` and
/// deals with the throw (ROLE-1.a).
public enum Reading<Value: Sendable & Equatable>: Sendable, Equatable {

    /// Somebody read this and it is the value given.
    case known(Value)

    /// Nobody could read this. It is not zero, and it is not empty.
    case unknown

    // MARK: - Public Methods

    /// True when the value was read.
    public var isKnown: Bool {
        switch self {
        case .known: return true
        case .unknown: return false
        }
    }

    /// The value, or a refusal naming what could not be read.
    ///
    /// Deliberately throwing rather than optional. An optional here would be
    /// unwrapped with a default by the first caller in a hurry, which is the
    /// exact mistake this type exists to prevent.
    ///
    /// - Parameter subject: What was being read, for the message.
    public func require(_ subject: String) throws -> Value {
        switch self {
        case .known(let value): return value
        case .unknown: throw UnreadableError(subject: subject)
        }
    }

    /// The same reading with its value transformed. Unknown stays unknown.
    public func map<Output: Sendable & Equatable>(_ transform: (Value) -> Output) -> Reading<Output> {
        switch self {
        case .known(let value): return .known(transform(value))
        case .unknown: return .unknown
        }
    }
}

/// Something a decision needed was never read.
public struct UnreadableError: Error, Equatable, LocalizedError, Sendable {

    // MARK: - Properties

    /// What could not be read, in words an operator recognises.
    public let subject: String

    // MARK: - Initializers

    /// - Parameter subject: What could not be read.
    public init(subject: String) {
        self.subject = subject
    }

    // MARK: - Public Methods

    public var errorDescription: String? {
        "\(subject) could not be read, so it is unknown rather than empty. "
            + "Nothing is granted or taken away on an unknown."
    }
}
