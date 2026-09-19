import Foundation
import Gating
import Testing
@testable import Chain

/// Turning one read of a wallet into what its owner holds.
@Suite("Reading one wallet")
internal struct WalletCheckTests {

    // MARK: - A wallet with nothing complicated in it

    @Test("A wallet holding the asset reports it, and says the answer is whole")
    internal func directHolding() throws {
        let check = WalletCheck.read(
            address: Fixture.wallet(1),
            holdings: [Fixture.holding(Fixture.assetId, 5_000_000)],
            token: try Fixture.token(),
            pools: [],
            reserves: [:]
        )
        #expect(check.directBalance.completeValue == 5_000_000)
        #expect(check.liquidityAmount.completeValue == 0)
        #expect(check.combinedBalance.completeValue == 5_000_000)
        #expect(check.canDecideEntitlements)
    }

    @Test("A wallet that really holds none of it reads as zero, because the node said so")
    internal func genuineZero() throws {
        let check = WalletCheck.read(
            address: Fixture.wallet(2),
            holdings: [],
            token: try Fixture.token(),
            pools: [],
            reserves: [:]
        )
        #expect(check.directBalance.completeValue == 0)
        #expect(check.heldAssetIds.completeValue == [])
        #expect(check.canDecideEntitlements)
    }

    @Test("Opting in without receiving anything is not holding anything")
    internal func zeroBalanceOptInIsNotAHolding() throws {
        let check = WalletCheck.read(
            address: Fixture.wallet(3),
            holdings: [
                Fixture.holding(Fixture.collectibleId, 0),
                Fixture.holding(Fixture.assetId, 10)
            ],
            token: try Fixture.token(),
            pools: [],
            reserves: [:]
        )
        #expect(check.heldAssetIds.completeValue == [Fixture.assetId])
    }

    // MARK: - A wallet with a pool position

    @Test("What is parked in a pool counts toward what somebody holds")
    internal func poolPositionsCount() throws {
        let pool = Fixture.pool()
        let reserves = Fixture.reserves(pool: pool)
        let check = WalletCheck.read(
            address: Fixture.wallet(4),
            holdings: [
                Fixture.holding(Fixture.assetId, 1_000_000),
                Fixture.holding(Fixture.lpAssetId, 100_000)
            ],
            token: try Fixture.token(),
            pools: [pool],
            reserves: [pool.id: reserves]
        )
        // A tenth of the pool tokens is a tenth of the counted side.
        #expect(check.liquidityAmount.completeValue == 100_000_000)
        #expect(check.combinedBalance.completeValue == 101_000_000)
        #expect(check.poolTokenBalances[pool.id] == 100_000)
    }

    @Test("A pool whose reserves could not be read leaves the total short, never smaller")
    internal func missingReservesLeaveItShort() throws {
        let pool = Fixture.pool()
        let check = WalletCheck.read(
            address: Fixture.wallet(5),
            holdings: [
                Fixture.holding(Fixture.assetId, 1_000_000),
                Fixture.holding(Fixture.lpAssetId, 100_000)
            ],
            token: try Fixture.token(),
            pools: [pool],
            reserves: [:]
        )
        // The direct holding is known and the pool position is not. Treating
        // the pool as zero here is what demoted the heaviest providers.
        #expect(check.directBalance.completeValue == 1_000_000)
        #expect(check.liquidityAmount.completeValue == nil)
        #expect(check.liquidityAmount.gaps == [.poolReservesUnavailable(poolId: pool.id)])
        #expect(check.combinedBalance.completeValue == nil)
        #expect(check.combinedBalance.valueEvenIfShort == 1_000_000)
        #expect(check.canDecideEntitlements == false)
    }

    @Test("A pool somebody has nothing in needs no reserves, so the total stays whole")
    internal func emptyPoolNeedsNoReserves() throws {
        let pool = Fixture.pool()
        let check = WalletCheck.read(
            address: Fixture.wallet(6),
            holdings: [Fixture.holding(Fixture.assetId, 42)],
            token: try Fixture.token(),
            pools: [pool],
            reserves: [:]
        )
        #expect(check.combinedBalance.completeValue == 42)
        #expect(check.poolTokenBalances[pool.id] == 0)
    }

    // MARK: - A wallet nobody could read

    @Test("A wallet that could not be read holds nothing known, rather than nothing")
    internal func unreadableWalletKnowsNothing() {
        let check = WalletCheck.unreadable(
            address: Fixture.wallet(7),
            gap: .requestFailed("timed out")
        )
        #expect(check.directBalance.valueEvenIfShort == nil)
        #expect(check.heldAssetIds.completeValue == nil)
        #expect(check.combinedBalance.completeValue == nil)
        #expect(check.canDecideEntitlements == false)
        #expect(HoldingsCacheWrite.persistableAssetIds(from: check.heldAssetIds) == nil)
    }

    // MARK: - Adding a person's wallets up

    @Test("Everything I hold is counted together, across every wallet I have linked")
    internal func walletsAreAddedUp() throws {
        let token = try Fixture.token()
        let checks = [
            WalletCheck.read(
                address: Fixture.wallet(1),
                holdings: [Fixture.holding(Fixture.assetId, 1_000)],
                token: token,
                pools: [],
                reserves: [:]
            ),
            WalletCheck.read(
                address: Fixture.wallet(2),
                holdings: [Fixture.holding(Fixture.assetId, 2_500)],
                token: token,
                pools: [],
                reserves: [:]
            )
        ]
        // Spelled out rather than inferred: there is one `CombinedBalance` in
        // the package now, and it is the layer above's. Both modules used to
        // declare one, both carried a comment about the same morning, and a
        // host importing the two had to qualify the name to say which
        // incident it meant.
        let combined: Gating.CombinedBalance.Totals = try BalanceCombiner.combine(checks).requireComplete()
        #expect(combined.accountCount == 2)
        #expect(combined.direct == 3_500)
        #expect(combined.combined == 3_500)
        #expect(combined.otherAccountsExist)
    }

    @Test("One unreadable wallet makes the whole person's total short, not just that wallet's")
    internal func oneBadWalletShortensTheWholeTotal() throws {
        let checks = [
            WalletCheck.read(
                address: Fixture.wallet(1),
                holdings: [Fixture.holding(Fixture.assetId, 1_000)],
                token: try Fixture.token(),
                pools: [],
                reserves: [:]
            ),
            WalletCheck.unreadable(address: Fixture.wallet(2), gap: .requestFailed("timed out"))
        ]
        let reading = BalanceCombiner.combine(checks)
        #expect(reading.isComplete == false)
        #expect(reading.valueEvenIfShort?.combined == 1_000)
        #expect(throws: ChainError.self) {
            _ = try reading.requireComplete()
        }
    }

    @Test("A newly linked, empty wallet does not strip a tier earned on another address")
    internal func storedBalancesStandInForUnreadWallets() throws {
        // Verification reads only the wallet that just signed. The others come
        // from what is already on record, which is what the periodic sweep
        // would have used anyway.
        let checks = [
            WalletCheck.read(
                address: Fixture.wallet(1),
                holdings: [],
                token: try Fixture.token(),
                pools: [],
                reserves: [:]
            ),
            WalletCheck.unreadable(address: Fixture.wallet(2), gap: .notRead)
        ]
        let combined = try BalanceCombiner
            .combine(checks, storedBalances: [Fixture.wallet(2): 9_000_000])
            .requireComplete()
        #expect(combined.combined == 9_000_000)
        #expect(combined.accountsFromStoredBalances == [Fixture.wallet(2)])
    }

    @Test("A stored figure is never used for a pool position, because a pool moves with every trade")
    internal func storedFiguresDoNotCoverPools() throws {
        let pool = Fixture.pool()
        let check = WalletCheck.read(
            address: Fixture.wallet(1),
            holdings: [Fixture.holding(Fixture.lpAssetId, 5)],
            token: try Fixture.token(),
            pools: [pool],
            reserves: [:]
        )
        let reading = BalanceCombiner.combine([check], storedBalances: [Fixture.wallet(1): 500])
        #expect(reading.isComplete == false)
        #expect(reading.gaps == [.poolReservesUnavailable(poolId: pool.id)])
    }

    @Test("A pool position too small to be worth a whole unit is still a pool position")
    internal func tinyPositionsStillCountAsLiquidity() throws {
        // The badge is for having put something in, not for what today's price
        // makes of it. One token out of a million of a pool holding a hundred
        // of the counted side rounds down to nothing and is still liquidity.
        //
        // Asked of the position rather than of the total, because that is
        // where the rules ask it: `LiquidityPosition.isProviding` reads the
        // LP holding, which is the evidence that somebody provided, and the
        // counted amount is what the position is worth today.
        let pool = Fixture.pool()
        let check = WalletCheck.read(
            address: Fixture.wallet(1),
            holdings: [Fixture.holding(Fixture.lpAssetId, 1)],
            token: try Fixture.token(),
            pools: [pool],
            reserves: [
                pool.id: Fixture.reserves(
                    pool: pool,
                    counted: 100,
                    other: 100,
                    circulating: 1_000_000
                )
            ]
        )
        let combined = try BalanceCombiner.combine([check]).requireComplete()
        #expect(combined.liquidity == 0)

        let holdings = MemberHoldings.fromChain(
            memberId: "member-1",
            isVerified: true,
            checks: [check],
            pools: [pool]
        )
        #expect(holdings.isProvidingLiquidity == .known(true))
        #expect(holdings.position(inPool: pool.id) == .known(
            LiquidityPosition(poolId: pool.id, lpBaseUnits: 1, tokenBaseUnits: 0)
        ))
    }

    @Test("Adding up absurd balances gives an absurd number rather than taking the process down")
    internal func totalsSaturateRatherThanTrap() throws {
        let token = try Fixture.token()
        let checks = (0..<3).map { index in
            WalletCheck.read(
                address: Fixture.wallet(index),
                holdings: [Fixture.holding(Fixture.assetId, UInt64.max)],
                token: token,
                pools: [],
                reserves: [:]
            )
        }
        let combined = try BalanceCombiner.combine(checks).requireComplete()
        #expect(combined.combined == UInt64.max)
    }

    @Test("Nobody's wallets is not a total of nothing, because nobody looked")
    internal func noWalletsIsNotAZero() {
        // This used to answer a complete zero, while the same question one
        // layer up answered unknown, and the two now produce the same type.
        // A caller reaches an empty list both when a member really has no
        // account and when nobody could list the accounts they have, and a
        // confident zero for the second strips every rung from somebody whose
        // holdings nobody read.
        let reading = BalanceCombiner.combine([])
        #expect(reading.isComplete == false)
        #expect(reading.valueEvenIfShort == nil)
        #expect(reading.gaps == [.notRead])
    }
}
