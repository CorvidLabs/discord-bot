import Foundation

/// What one person holds, added up across every wallet they have linked.
public struct CombinedBalance: Sendable, Equatable {

    // MARK: - Properties

    /// How many wallets went into it.
    public let walletCount: Int

    /// The configured asset held directly, across all of them.
    public let directBalance: UInt64

    /// The counted asset attributable to pool positions, across all of them.
    public let liquidityAmount: UInt64

    /// The two added together. This is the number a tier is decided on.
    public let combinedBalance: UInt64

    /// Whether any wallet has a pool position at all, which is worth a badge
    /// of its own however small it is.
    public let hasLiquidity: Bool

    /// Wallets whose figure came from a stored balance rather than a fresh
    /// read, so an operator can tell how old the answer is.
    public let walletsFromStoredBalances: [String]

    // MARK: - Initializers

    /// The total is derived rather than passed in, so it cannot disagree
    /// with its two halves.
    public init(
        walletCount: Int,
        directBalance: UInt64,
        liquidityAmount: UInt64,
        hasLiquidity: Bool,
        walletsFromStoredBalances: [String] = []
    ) {
        self.walletCount = walletCount
        self.directBalance = directBalance
        self.liquidityAmount = liquidityAmount
        self.combinedBalance = directBalance.saturatingAdding(liquidityAmount)
        self.hasLiquidity = hasLiquidity
        self.walletsFromStoredBalances = walletsFromStoredBalances
    }
}

/// Adding a person's wallets up without losing what could not be read.
///
/// The arithmetic is trivial and the completeness is not, which is why this is
/// its own type with its own tests. One unreadable wallet out of four makes the
/// **whole** total short: the three that were read are a real number, it is
/// simply not this person's number, and deciding anything on it is deciding on
/// a fraction of what they hold.
public enum BalanceCombiner: Sendable {

    // MARK: - Public Methods

    /// - Parameters:
    ///   - checks: One reading per linked wallet.
    ///   - storedBalances: Balances already on record, by wallet address, for
    ///     wallets that were not read this time.
    /// - Returns: The total, complete only when nothing is missing from it.
    ///
    /// The stored balances are not a convenience. Verification reads only the
    /// wallet that has just signed, and a person linking a second, empty wallet
    /// would otherwise be totalled at whatever that empty wallet holds and
    /// stripped of a tier they earned on the first one. A stored figure
    /// standing in for a wallet nobody read this time is a complete answer, and
    /// is recorded as such so somebody can see where it came from.
    public static func combine(
        _ checks: [WalletCheck],
        storedBalances: [String: UInt64] = [:]
    ) -> ChainReading<CombinedBalance> {
        var direct: UInt64 = 0
        var liquidity: UInt64 = 0
        var hasLiquidity = false
        var gaps: [ChainReadGap] = []
        var fromStored: [String] = []

        for check in checks {
            // The badge is for having a position, not for the position being
            // worth something. A share of the counted side that rounds down to
            // nothing is still liquidity somebody provided, and the pool token
            // balance is the record of it.
            if check.poolTokenBalances.values.contains(where: { $0 > 0 }) {
                hasLiquidity = true
            }
            guard let readDirectly = check.directBalance.completeValue else {
                // Nothing was read for this wallet. A figure already on record
                // stands in for the whole of it, direct holding and pool
                // position together, because that is what was last known about
                // it and it is what the periodic sweep would have used.
                if let stored = storedBalances[check.address] {
                    direct = direct.saturatingAdding(stored)
                    fromStored.append(check.address)
                } else {
                    gaps.append(contentsOf: check.directBalance.gaps)
                    gaps.append(contentsOf: check.liquidityAmount.gaps)
                }
                continue
            }
            direct = direct.saturatingAdding(readDirectly)

            if let amount = check.liquidityAmount.completeValue {
                liquidity = liquidity.saturatingAdding(amount)
                if amount > 0 { hasLiquidity = true }
            } else {
                // No stored fallback for pool positions on purpose: a stored
                // pool figure is worth what the pool was worth when it was
                // stored, and a pool's value moves with every trade.
                if let partial = check.liquidityAmount.valueEvenIfShort, partial > 0 {
                    hasLiquidity = true
                }
                gaps.append(contentsOf: check.liquidityAmount.gaps)
            }
        }

        let combined = CombinedBalance(
            walletCount: checks.count,
            directBalance: direct,
            liquidityAmount: liquidity,
            hasLiquidity: hasLiquidity,
            walletsFromStoredBalances: fromStored
        )
        return gaps.isEmpty ? .complete(combined) : .short(combined, gaps: gaps)
    }
}
