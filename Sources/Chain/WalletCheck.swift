import Foundation
import Gating

/// One wallet, read once: what it holds directly, what its pool positions are
/// worth, and which parts of that could not be established.
///
/// The completeness is not decoration. A failed pool fetch reads exactly like
/// an empty pool and a failed asset list reads exactly like a wallet that sold
/// everything, so every number here is a ``ChainReading`` rather than a bare
/// integer: a caller that wants a figure it may act on has to ask for a
/// complete one.
public struct WalletCheck: Sendable, Equatable {

    // MARK: - Properties

    /// The wallet this describes.
    public let address: String

    /// Everything the wallet has opted into, held or not.
    public let holdings: ChainReading<[ChainHolding]>

    /// The configured token held directly in this wallet.
    public let directBalance: ChainReading<UInt64>

    /// The counted token attributable to this wallet's pool positions.
    ///
    /// Short when a pool's reserves were not available: the wallet's pool
    /// tokens were read, but without reserves there is no way to say what they
    /// are worth, and calling that zero is how a liquidity provider is demoted
    /// for providing liquidity.
    public let liquidityAmount: ChainReading<UInt64>

    /// Pool tokens held, by pool id, for the pools that were read.
    public let poolTokenBalances: [String: UInt64]

    /// What each pool position is worth of the counted token, by pool id.
    ///
    /// Only the pools whose reserves were read appear here. A pool whose
    /// reserves were missing is **absent**, and named in ``liquidityAmount``'s
    /// gaps, rather than present as a zero: a zero here would travel into a
    /// position worth nothing and demote the provider, which is the failure
    /// this whole type is shaped around. Kept per pool as well as summed into
    /// ``liquidityAmount`` so a caller can build one
    /// ``Gating/LiquidityPosition`` per pool without reading the reserves
    /// again.
    public let poolCountedAmounts: [String: UInt64]

    // MARK: - Initializers

    /// Built by ``read(address:holdings:token:pools:reserves:)`` or
    /// ``unreadable(address:gap:)``. Public so a host can rebuild one from
    /// figures it stored earlier.
    ///
    /// - Parameters:
    ///   - address: The wallet this describes.
    ///   - holdings: Everything it has opted into, held or not.
    ///   - directBalance: The configured token held directly.
    ///   - liquidityAmount: The counted token its pool positions are worth.
    ///   - poolTokenBalances: Pool tokens held, by pool id.
    ///   - poolCountedAmounts: What each position is worth, by pool id, for
    ///     the pools whose reserves were read.
    public init(
        address: String,
        holdings: ChainReading<[ChainHolding]>,
        directBalance: ChainReading<UInt64>,
        liquidityAmount: ChainReading<UInt64>,
        poolTokenBalances: [String: UInt64],
        poolCountedAmounts: [String: UInt64]
    ) {
        self.address = address
        self.holdings = holdings
        self.directBalance = directBalance
        self.liquidityAmount = liquidityAmount
        self.poolTokenBalances = poolTokenBalances
        self.poolCountedAmounts = poolCountedAmounts
    }

    // MARK: - Public Methods

    /// Builds a check from a completed read of a wallet's holdings.
    ///
    /// All of the interpretation lives here, away from the network, so every
    /// case below can be pinned by a test: a wallet in no pools, a wallet whose
    /// pool has no reserves, a wallet holding pool tokens of a pool nobody
    /// configured.
    ///
    /// - Parameters:
    ///   - address: The wallet.
    ///   - holdings: What it holds, from a read that completed.
    ///   - token: The token counted directly.
    ///   - pools: The pools an operator wants counted.
    ///   - reserves: Reserves by pool id. A pool missing from this is a gap,
    ///     never a zero.
    public static func read(
        address: String,
        holdings: [ChainHolding],
        token: TokenProfile,
        pools: [LiquidityPool],
        reserves: [String: PoolReserves]
    ) -> WalletCheck {
        var poolTokenBalances: [String: UInt64] = [:]
        var poolCountedAmounts: [String: UInt64] = [:]
        var liquidity: UInt64 = 0
        var gaps: [ChainReadGap] = []

        for pool in pools {
            let held = holdings.amount(of: pool.lpAssetId)
            poolTokenBalances[pool.id] = held
            guard held > 0 else {
                poolCountedAmounts[pool.id] = 0
                continue
            }
            guard let reserve = reserves[pool.id] else {
                // Holding pool tokens whose pool could not be read. The amount
                // is unknown and is emphatically not zero, so this pool is
                // left out of `poolCountedAmounts` rather than written as a 0.
                gaps.append(.poolReservesUnavailable(poolId: pool.id))
                continue
            }
            let counted = reserve.share(ofPoolTokens: held).countedAssetAmount
            poolCountedAmounts[pool.id] = counted
            liquidity = liquidity.saturatingAdding(counted)
        }

        return WalletCheck(
            address: address,
            holdings: .complete(holdings),
            directBalance: .complete(holdings.amount(of: token.assetId)),
            liquidityAmount: gaps.isEmpty ? .complete(liquidity) : .short(liquidity, gaps: gaps),
            poolTokenBalances: poolTokenBalances,
            poolCountedAmounts: poolCountedAmounts
        )
    }

    /// Builds a check for a wallet that could not be read at all.
    ///
    /// Everything is unavailable rather than zero. This is the case that
    /// demoted people: the wallet looked empty because nobody could see it.
    public static func unreadable(address: String, gap: ChainReadGap) -> WalletCheck {
        WalletCheck(
            address: address,
            holdings: .unavailable(gaps: [gap]),
            directBalance: .unavailable(gaps: [gap]),
            liquidityAmount: .unavailable(gaps: [gap]),
            poolTokenBalances: [:],
            poolCountedAmounts: [:]
        )
    }

    /// The assets this wallet actually holds. Opted-in zeros are not holdings.
    public var heldAssetIds: ChainReading<[UInt64]> {
        holdings.map(\.positiveBalanceAssetIds)
    }

    /// Direct holding plus pool positions.
    ///
    /// Complete only when both parts are. Anything else is short by an unknown
    /// amount, and a tier decided on it is a tier somebody loses for no reason.
    public var combinedBalance: ChainReading<UInt64> {
        let gaps = directBalance.gaps + liquidityAmount.gaps
        let direct = directBalance.valueEvenIfShort
        let liquidity = liquidityAmount.valueEvenIfShort
        guard let direct else { return .unavailable(gaps: gaps.isEmpty ? [.notRead] : gaps) }
        let total = direct.saturatingAdding(liquidity ?? 0)
        return gaps.isEmpty ? .complete(total) : .short(total, gaps: gaps)
    }

    /// Whether this reading may be used to decide what the wallet's owner has
    /// earned.
    public var canDecideEntitlements: Bool {
        combinedBalance.isComplete
    }
}

extension UInt64 {

    /// Addition that saturates instead of trapping.
    ///
    /// Summing balances across a member's wallets cannot overflow with real
    /// holdings, and a process taken down by a stubbed or malformed reading is
    /// a worse answer than a number that is obviously wrong.
    internal func saturatingAdding(_ other: UInt64) -> UInt64 {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? UInt64.max : sum
    }
}

/// Whether a combined balance may be used to decide what somebody has earned.
///
/// Split out from the code that acts on it so the rule itself can be tested.
/// The decision is the part that regressed, so the decision is what gets
/// pinned.
public enum LiquidityCompleteness: Sendable {

    /// - Parameters:
    ///   - liquidityIncomplete: At least one pool figure could not be read.
    ///   - cacheSuppliedLiquidity: Stored holdings stood in for every missing
    ///     pool, so nothing is actually missing from the total.
    /// - Returns: `false` when the total is short by an unknown amount, in
    ///   which case roles are left exactly as they are rather than recomputed.
    ///
    /// An incomplete read with no stored holdings to fall back on is the case
    /// that demoted the heaviest liquidity providers in the room: the total
    /// looks like a real number, and nothing in it says a pool is missing.
    public static func canDecideTier(
        liquidityIncomplete: Bool,
        cacheSuppliedLiquidity: Bool
    ) -> Bool {
        !liquidityIncomplete || cacheSuppliedLiquidity
    }
}

/// Whether a role that depends on holding something from a collection may be
/// granted or taken away.
///
/// Granting on a partial positive read is safe: something was seen, and seeing
/// it is the whole test. **Taking one away requires a complete negative read**,
/// because the alternative is stripping a role from everybody whose wallet
/// happened to be unreadable this sweep and handing it back on the next one.
/// A role that flickers on and off is worse than a role that is a sweep out of
/// date.
public enum CollectionCompleteness: Sendable {

    /// - Parameters:
    ///   - holdingsComplete: Every one of the member's wallets was really read.
    ///   - heldNothing: The wallets that were read held no assets at all.
    ///   - registryAnswered: The catalogue of the collection's assets answered.
    ///   - matchCount: How many of the held assets belong to the collection.
    ///     Meaningless unless the catalogue answered.
    /// - Returns: `true` to grant, `false` to take away, `nil` to leave the
    ///   member's roles exactly as they are.
    public static func decidedHoldsCollection(
        holdingsComplete: Bool,
        heldNothing: Bool,
        registryAnswered: Bool,
        matchCount: Int = 0
    ) -> Bool? {
        if heldNothing {
            return holdingsComplete ? false : nil
        }
        if !registryAnswered {
            return nil
        }
        if matchCount > 0 {
            return true
        }
        return holdingsComplete ? false : nil
    }
}

/// Whether a reading of what a wallet holds may be written to a store that
/// other work reads later.
///
/// An incomplete read must never be stored as an empty one. A payout that reads
/// a stored holdings list treats an empty list as "holds nothing" and pays a
/// short list, when what it should do is refuse to run at all. The gap is
/// invisible by then: the store cannot say whether a wallet holds nothing or
/// was never successfully read.
public enum HoldingsCacheWrite: Sendable {

    /// - Parameters:
    ///   - holdingsIncomplete: Whether the read that produced this list failed.
    ///   - heldAssetIds: What was read.
    /// - Returns: The ids to store, or nil when the caller must write nothing
    ///   at all and leave whatever is already there.
    public static func persistableAssetIds(
        holdingsIncomplete: Bool,
        heldAssetIds: [UInt64]
    ) -> [UInt64]? {
        holdingsIncomplete ? nil : heldAssetIds
    }

    /// The same rule, taken straight from a reading.
    public static func persistableAssetIds(from reading: ChainReading<[UInt64]>) -> [UInt64]? {
        reading.completeValue
    }
}
