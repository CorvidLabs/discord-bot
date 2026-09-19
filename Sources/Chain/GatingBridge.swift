import Foundation
import Gating

/// Turning what the chain said into what the rules may decide on.
///
/// Two types were written for the same production incident, one in each
/// module, and for a while nothing joined them up. ``ChainReading`` says
/// whether an answer is whole; ``Gating/Reading`` says whether a fact was read
/// at all. A host with a `ChainReading` and a rule set wanting a `Reading` had
/// exactly one accessor that hands back a number from a short answer,
/// ``ChainReading/valueEvenIfShort``, so the obvious line to write was
/// `.known(reading.valueEvenIfShort ?? 0)`.
///
/// That line is the incident. A pool whose reserves did not load makes the
/// total `.short`, `valueEvenIfShort` hands over the part that was read, the
/// `?? 0` turns a wallet nobody could see into a wallet holding nothing, and
/// every liquidity provider in the server is demoted for a provider error that
/// lasted a minute. Both types exist to stop that, and the seam between them
/// is where it came back.
///
/// So the join lives here, in the module that already depends on the other
/// one, under one rule: **a short answer is not a smaller true answer.**
///
/// The rule is stated in two places because there are two shapes of it, and
/// neither is the other. ``ChainReading/gatingReading`` is the rule for ONE
/// reading. The aggregations below apply it to MANY, where it becomes: one
/// wallet short makes the whole member unknown, because three wallets out of
/// four is a real number and it is not this person's number. Do not replace
/// an aggregation with a per-reading conversion and a sum, which is how a
/// partial total gets through while still looking careful.
extension ChainReading where Value: Equatable {

    // MARK: - Public Methods

    /// This reading as the one the rules read.
    ///
    /// `complete` becomes ``Gating/Reading/known(_:)``. **Both** `short` and
    /// `unavailable` become ``Gating/Reading/unknown``, and that is the whole
    /// content of this property: a partial total is evidence of nothing, and
    /// the rules leave every role a fact decides exactly where it is when the
    /// fact is unknown (ROLE-1.a). There is deliberately no variant that
    /// takes a default, and no variant that lets a short answer through.
    public var gatingReading: Reading<Value> {
        switch self {
        case .complete(let value):
            return .known(value)
        case .short, .unavailable:
            return .unknown
        }
    }
}

extension MemberHoldings {

    // MARK: - Reading a member off the chain

    /// What one member holds, from the wallets that were read for them.
    ///
    /// The other half of the join. Nothing built a ``MemberHoldings`` from
    /// what the chain said, so the one type the rules take as input had to be
    /// assembled by hand at every call site, which is how a `?? 0` gets
    /// written. Every rule below is the conservative one:
    ///
    /// - **No wallets at all is unknown**, never zeroes. The caller reaches an
    ///   empty list both when the member has no account and when nobody could
    ///   list their accounts, and those want opposite decisions. A member who
    ///   provably has none is ``unlinked(memberId:configuration:)``.
    /// - **One wallet short makes the whole member unknown.** Three wallets
    ///   out of four is a real number and it is not this person's number.
    /// - **The positions are all or nothing**, which is what
    ///   ``liquidityPositions`` documents and what lets a pool a member is
    ///   absent from read as a zero position rather than as a gap.
    /// - **A collection nobody looked up is left out**, so
    ///   ``count(ofCollection:)`` answers unknown and its roles are held
    ///   rather than taken away.
    ///
    /// Stored balances are deliberately not a parameter. Blending a figure
    /// from the store into a reading belongs to the moment a member links an
    /// account, where `Gating.CombinedBalance.afterLinking` already does it
    /// and says so in its name. Doing it silently here would hide how old
    /// half of a sweep's answer was.
    ///
    /// - Parameters:
    ///   - memberId: Who this is.
    ///   - isVerified: Whether they have a verified account at all. This
    ///     bot's own record, not something the chain can say, which is why it
    ///     has no default here. The layer below removed the default it used to
    ///     carry, because a caller who forgot it granted the badge rather than
    ///     holding it, and this is now the usual way holdings are built: a
    ///     default here would put that mistake straight back.
    ///   - checks: One reading per wallet the member has verified.
    ///   - pools: The pools the operator counts, as
    ///     ``Gating/LiquidityConfiguration`` loaded them.
    ///   - collections: The collections the operator gates on.
    ///   - assetCollections: Which collection each asset belongs to, as the
    ///     host's registry resolved it. Unknown by default, because a registry
    ///     that did not answer must not read as a member holding none of them.
    public static func fromChain(
        memberId: String,
        isVerified: Bool,
        checks: [WalletCheck],
        pools: [LiquidityPool],
        collections: CollectionCatalog = CollectionCatalog(),
        assetCollections: Reading<[UInt64: String]> = .unknown
    ) -> MemberHoldings {
        guard !checks.isEmpty else {
            return MemberHoldings(memberId: memberId, isVerified: isVerified)
        }
        return MemberHoldings(
            memberId: memberId,
            isVerified: isVerified,
            directBalance: directBalance(from: checks),
            liquidityPositions: liquidityPositions(from: checks, pools: pools),
            collectionCounts: collectionCounts(
                from: checks,
                collections: collections,
                assetCollections: assetCollections
            )
        )
    }

    // MARK: - Private Methods

    /// The configured token held directly, summed, or unknown when any wallet
    /// was short of it.
    private static func directBalance(from checks: [WalletCheck]) -> Reading<UInt64> {
        var total: UInt64 = 0
        for check in checks {
            guard let read = check.directBalance.completeValue else { return .unknown }
            total = total.saturatingAdding(read)
        }
        return .known(total)
    }

    /// One position per pool the member is actually in, or unknown when any
    /// wallet's pool figures were short.
    ///
    /// A pool the member holds none of is left out rather than listed as a
    /// zero, because ``position(inPool:)`` already answers a zero position for
    /// a pool that is absent from a list that was read.
    private static func liquidityPositions(
        from checks: [WalletCheck],
        pools: [LiquidityPool]
    ) -> Reading<[LiquidityPosition]> {
        guard checks.allSatisfy({ $0.liquidityAmount.isComplete }) else { return .unknown }
        var positions: [LiquidityPosition] = []
        for pool in pools {
            var lpBaseUnits: UInt64 = 0
            var tokenBaseUnits: UInt64 = 0
            for check in checks {
                lpBaseUnits = lpBaseUnits.saturatingAdding(check.poolTokenBalances[pool.id] ?? 0)
                tokenBaseUnits = tokenBaseUnits.saturatingAdding(check.poolCountedAmounts[pool.id] ?? 0)
            }
            guard lpBaseUnits > 0 || tokenBaseUnits > 0 else { continue }
            positions.append(
                LiquidityPosition(
                    poolId: pool.id,
                    lpBaseUnits: lpBaseUnits,
                    tokenBaseUnits: tokenBaseUnits
                )
            )
        }
        return .known(positions)
    }

    /// How many pieces of each configured collection the member holds.
    ///
    /// Empty when either half of the question went unanswered: the wallets
    /// were not all read, or the registry that says which asset belongs to
    /// which collection did not answer. A collection left out of the
    /// dictionary reads as unknown, which holds its roles;
    /// a collection present with a zero takes them away, and that is only
    /// honest when both halves really answered.
    private static func collectionCounts(
        from checks: [WalletCheck],
        collections: CollectionCatalog,
        assetCollections: Reading<[UInt64: String]>
    ) -> [String: Reading<Int>] {
        guard
            !collections.isEmpty,
            case .known(let membership) = assetCollections
        else { return [:] }
        var held: [UInt64] = []
        for check in checks {
            guard let ids = check.heldAssetIds.completeValue else { return [:] }
            held.append(contentsOf: ids)
        }
        var counts: [String: Reading<Int>] = [:]
        for collection in collections.collections {
            counts[collection.id] = .known(held.filter { membership[$0] == collection.id }.count)
        }
        return counts
    }
}
