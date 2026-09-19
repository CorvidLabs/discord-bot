import Foundation
import Gating

/// Adding a person's wallets up without losing what could not be read.
///
/// The arithmetic is trivial and the completeness is not, which is why this is
/// its own type with its own tests. One unreadable wallet out of four makes the
/// **whole** total short: the three that were read are a real number, it is
/// simply not this person's number, and deciding anything on it is deciding on
/// a fraction of what they hold.
///
/// The total itself is ``Gating/CombinedBalance/Totals``. This module used to
/// declare a second `CombinedBalance` of its own, and both carried a comment
/// about the same morning: a member demoted for linking a second, empty
/// wallet. Two types with one name, written for one incident, in two modules a
/// host imports together, is how the third version of that incident happens.
/// The one in ``Gating`` stays, because it is the layer the rules are decided
/// in and the shape they are decided from; the facts this one had that it
/// lacked, how many accounts went into the total and which of them stood in on
/// a stored figure, moved there rather than being kept in a rival type.
public enum BalanceCombiner: Sendable {

    // MARK: - Public Methods

    /// - Parameters:
    ///   - checks: One reading per linked wallet.
    ///   - storedBalances: Balances already on record, by wallet address, for
    ///     wallets that were not read this time.
    /// - Returns: The total, complete only when nothing is missing from it.
    ///
    /// **No wallets at all is `unavailable`, never a total of nothing.** A
    /// caller reaches an empty list two ways and they want opposite
    /// decisions: the member genuinely has no account, or nobody could list
    /// the accounts they have. ``Gating/CombinedBalance/across(_:)`` answers
    /// the same question the same way, one layer up, and the two agreeing is
    /// the point: a confident zero here would read as a member who sold
    /// everything and strip every rung from somebody whose holdings nobody
    /// looked at. A member who provably has no account is
    /// ``Gating/MemberHoldings/unlinked(memberId:configuration:)``.
    ///
    /// The stored balances are not a convenience either. Verification reads
    /// only the wallet that has just signed, and a person linking a second,
    /// empty wallet would otherwise be totalled at whatever that empty wallet
    /// holds and stripped of a tier they earned on the first one. A stored
    /// figure standing in for a wallet nobody read this time is a complete
    /// answer, and is recorded as such so somebody can see where it came from.
    public static func combine(
        _ checks: [WalletCheck],
        storedBalances: [String: UInt64] = [:]
    ) -> ChainReading<CombinedBalance.Totals> {
        guard !checks.isEmpty else { return .unavailable(gaps: [.notRead]) }

        var direct: UInt64 = 0
        var liquidity: UInt64 = 0
        var gaps: [ChainReadGap] = []
        var fromStored: [String] = []

        for check in checks {
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
            } else {
                // No stored fallback for pool positions on purpose: a stored
                // pool figure is worth what the pool was worth when it was
                // stored, and a pool's value moves with every trade.
                gaps.append(contentsOf: check.liquidityAmount.gaps)
            }
        }

        let totals = CombinedBalance.Totals(
            direct: direct,
            liquidity: liquidity,
            combined: direct.saturatingAdding(liquidity),
            otherAccountsExist: checks.count > 1,
            accountCount: checks.count,
            accountsFromStoredBalances: fromStored
        )
        return gaps.isEmpty ? .complete(totals) : .short(totals, gaps: gaps)
    }
}
