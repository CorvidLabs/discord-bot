import Foundation

/// Everything the rules know about one member, and how much of it was
/// actually read.
///
/// Summed across every account the member has verified, because the ladder is
/// about the person and not about one wallet. Every field that could fail to
/// be read is a ``Reading``, and a field nobody asked about is `.unknown`
/// rather than empty: the caller that could not reach a data provider and the
/// caller that found nothing are different callers, and they want opposite
/// decisions (ROLE-1.a).
public struct MemberHoldings: Sendable, Equatable {

    // MARK: - Properties

    /// Who this is. A Discord user id at the boundary, a string here.
    public let memberId: String

    /// Whether the member has any verified account at all.
    ///
    /// Not a reading: a linked account is this bot's own record, and if it
    /// cannot read its own records it has nothing to decide with.
    public let isVerified: Bool

    /// The gated token held directly, summed across accounts, in base units.
    ///
    /// Summed over **no** accounts is `.unknown`, not `.known(0)`. A caller
    /// that could not list the member's accounts holds no evidence about what
    /// they have, and ``CombinedBalance/across(_:)`` answers that way so the
    /// zero cannot be written here by accident. A member who provably has no
    /// account at all is ``unlinked(memberId:configuration:)``.
    public let directBalance: Reading<UInt64>

    /// Every liquidity position, across accounts and pools.
    ///
    /// One reading for the lot. A partial list is exactly the failure that
    /// demotes a provider, so the caller either has all of them or says it
    /// has none of them.
    public let liquidityPositions: Reading<[LiquidityPosition]>

    /// How many pieces of each collection the member holds, keyed by
    /// collection id.
    private let collectionCounts: [String: Reading<Int>]

    // MARK: - Initializers

    /// - Parameters:
    ///   - memberId: Who this is.
    ///   - isVerified: Whether they have a verified account.
    ///   - directBalance: The gated token held directly, in base units.
    ///   - liquidityPositions: Every position, or unknown.
    ///   - collectionCounts: Pieces held per collection id. A collection left
    ///     out reads as unknown, never as zero.
    public init(
        memberId: String,
        isVerified: Bool = true,
        directBalance: Reading<UInt64> = .unknown,
        liquidityPositions: Reading<[LiquidityPosition]> = .unknown,
        collectionCounts: [String: Reading<Int>] = [:]
    ) {
        self.memberId = memberId
        self.isVerified = isVerified
        self.directBalance = directBalance
        self.liquidityPositions = liquidityPositions
        self.collectionCounts = collectionCounts
    }

    // MARK: - Public Methods

    /// How many pieces of this collection the member holds.
    ///
    /// A collection nobody asked about comes back `.unknown`. The dictionary
    /// is private for exactly this reason: a subscript returning `Int?` would
    /// be read as `?? 0` by the first caller in a hurry, and a collection that
    /// was never looked up would strip the role of everybody who holds one.
    public func count(ofCollection id: String) -> Reading<Int> {
        collectionCounts[id] ?? .unknown
    }

    /// The gated token held directly plus the gated token inside every
    /// position.
    ///
    /// Unknown unless both halves were read. What a member has parked in a
    /// pool has not stopped being theirs, and treating a provider as a
    /// non-holder feels like a punishment for providing (ROLE-2).
    ///
    /// Saturating rather than wrapping: two balances that overflow put a
    /// member on the top rung, which is visible and wrong in the harmless
    /// direction. Wrapping would put the largest holder in the server on no
    /// rung at all.
    public var combinedBalance: Reading<UInt64> {
        guard
            case .known(let direct) = directBalance,
            case .known(let positions) = liquidityPositions
        else { return .unknown }
        var total = direct
        for position in positions {
            let (sum, overflowed) = total.addingReportingOverflow(position.tokenBaseUnits)
            total = overflowed ? UInt64.max : sum
        }
        return .known(total)
    }

    /// The gated token inside every position, or unknown.
    public var liquidityBalance: Reading<UInt64> {
        liquidityPositions.map { positions in
            positions.reduce(UInt64(0)) { running, position in
                let (sum, overflowed) = running.addingReportingOverflow(position.tokenBaseUnits)
                return overflowed ? UInt64.max : sum
            }
        }
    }

    /// True when the member holds any of any pool's LP token.
    public var isProvidingLiquidity: Reading<Bool> {
        liquidityPositions.map { positions in positions.contains { $0.isProviding } }
    }

    /// The member's position in one pool, or unknown when the positions were
    /// not read.
    ///
    /// A pool the member is absent from reads as a zero position, because a
    /// read list that does not mention a pool genuinely means they are not in
    /// it. That is only true because the list is all-or-nothing.
    public func position(inPool poolId: String) -> Reading<LiquidityPosition> {
        liquidityPositions.map { positions in
            positions.first { $0.poolId == poolId }
                ?? LiquidityPosition(poolId: poolId, lpBaseUnits: 0, tokenBaseUnits: 0)
        }
    }
}
