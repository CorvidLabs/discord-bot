import Foundation

/// A number the chain could not finish telling us, and what was missing.
///
/// These are not a taxonomy for its own sake. Each one is a way a reading can
/// come back looking exactly like a real, small answer.
public enum ChainReadGap: Sendable, Equatable, Hashable, Codable {

    /// The request failed. The account may hold anything at all.
    case requestFailed(String)

    /// A pool's reserves were not available, so a holding of its pool token
    /// could not be converted into an amount of the counted asset.
    case poolReservesUnavailable(poolId: String)

    /// The reading stopped because today's request budget is spent.
    case budgetSpent

    /// Nobody has read this yet. Distinct from a failure: nothing went wrong,
    /// the question was simply never asked.
    case notRead

    /// One line naming what is missing, for a message a person will read.
    public var summary: String {
        switch self {
        case .requestFailed(let detail):
            return "a request failed (\(detail))"
        case .poolReservesUnavailable(let poolId):
            return "pool `\(poolId)` reserves could not be read"
        case .budgetSpent:
            return "today's request budget is spent"
        case .notRead:
            return "it was never read"
        }
    }
}

/// An answer from the chain, carrying whether it is the whole answer.
///
/// **This type exists because of a production incident, and the shape of it is
/// the fix.** A failed liquidity fetch reads identically to an empty pool. A
/// failed asset list reads identically to somebody who sold everything. Both
/// arrive as zero, both look like a real answer, and acting on either as a zero
/// takes a role away from a member who did nothing wrong. Silence from a
/// provider is not evidence that a person sold up.
///
/// The earlier version of this carried a `Bool` beside the number. That worked
/// only for as long as every caller remembered the `Bool` existed, and one
/// caller not remembering is what demoted a room full of people. Here the
/// number a caller may act on comes only from ``requireComplete()`` or
/// ``completeValue``, and a short one has to be asked for by a name that says
/// it is short.
public enum ChainReading<Value: Sendable>: Sendable {

    /// Everything this reading needed was read.
    case complete(Value)

    /// Part of it could not be read. The value is what **was** read, and is
    /// known to be short by an unknown amount.
    case short(Value, gaps: [ChainReadGap])

    /// None of it could be read.
    case unavailable(gaps: [ChainReadGap])

    // MARK: - Public Methods

    /// The value, only when the reading is complete.
    public var completeValue: Value? {
        guard case .complete(let value) = self else { return nil }
        return value
    }

    /// The value even though it may be short, for a caller that has decided a
    /// partial answer is better than none.
    ///
    /// Named so that reaching for it is a decision somebody can see in review.
    /// Showing a member a balance that may be short is fine. Deciding what they
    /// are owed, or taking a role away, is not.
    public var valueEvenIfShort: Value? {
        switch self {
        case .complete(let value), .short(let value, _):
            return value
        case .unavailable:
            return nil
        }
    }

    /// The value, or a refusal naming what was missing.
    public func requireComplete() throws -> Value {
        switch self {
        case .complete(let value):
            return value
        case .short(_, let gaps), .unavailable(let gaps):
            throw ChainError.incompleteRead(gaps: gaps)
        }
    }

    /// Whether the whole answer arrived.
    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }

    /// What was missing. Empty when the reading is complete.
    public var gaps: [ChainReadGap] {
        switch self {
        case .complete:
            return []
        case .short(_, let gaps), .unavailable(let gaps):
            return gaps
        }
    }

    /// The same reading with its value transformed, keeping completeness.
    ///
    /// Completeness survives every hop on purpose: the moment a transformation
    /// drops it, the number at the other end looks whole again.
    public func map<Output: Sendable>(_ transform: (Value) -> Output) -> ChainReading<Output> {
        switch self {
        case .complete(let value):
            return .complete(transform(value))
        case .short(let value, let gaps):
            return .short(transform(value), gaps: gaps)
        case .unavailable(let gaps):
            return .unavailable(gaps: gaps)
        }
    }
}

extension ChainReading: Equatable where Value: Equatable {}
