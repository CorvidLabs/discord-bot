import Foundation
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
            asset: try Fixture.asset(),
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
            asset: try Fixture.asset(),
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
            asset: try Fixture.asset(),
            pools: [],
            reserves: [:]
        )
        #expect(check.heldAssetIds.completeValue == [Fixture.assetId])
    }

    // MARK: - A wallet with a pool position

    @Test("What is parked in a pool counts toward what somebody holds")
    internal func poolPositionsCount() throws {
        let pool = try Fixture.pool()
        let reserves = Fixture.reserves(pool: pool)
        let check = WalletCheck.read(
            address: Fixture.wallet(4),
            holdings: [
                Fixture.holding(Fixture.assetId, 1_000_000),
                Fixture.holding(Fixture.poolTokenId, 100_000)
            ],
            asset: try Fixture.asset(),
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
        let pool = try Fixture.pool()
        let check = WalletCheck.read(
            address: Fixture.wallet(5),
            holdings: [
                Fixture.holding(Fixture.assetId, 1_000_000),
                Fixture.holding(Fixture.poolTokenId, 100_000)
            ],
            asset: try Fixture.asset(),
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
        let pool = try Fixture.pool()
        let check = WalletCheck.read(
            address: Fixture.wallet(6),
            holdings: [Fixture.holding(Fixture.assetId, 42)],
            asset: try Fixture.asset(),
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
        let asset = try Fixture.asset()
        let checks = [
            WalletCheck.read(
                address: Fixture.wallet(1),
                holdings: [Fixture.holding(Fixture.assetId, 1_000)],
                asset: asset,
                pools: [],
                reserves: [:]
            ),
            WalletCheck.read(
                address: Fixture.wallet(2),
                holdings: [Fixture.holding(Fixture.assetId, 2_500)],
                asset: asset,
                pools: [],
                reserves: [:]
            )
        ]
        let combined = try BalanceCombiner.combine(checks).requireComplete()
        #expect(combined.walletCount == 2)
        #expect(combined.directBalance == 3_500)
        #expect(combined.combinedBalance == 3_500)
        #expect(combined.hasLiquidity == false)
    }

    @Test("One unreadable wallet makes the whole person's total short, not just that wallet's")
    internal func oneBadWalletShortensTheWholeTotal() throws {
        let checks = [
            WalletCheck.read(
                address: Fixture.wallet(1),
                holdings: [Fixture.holding(Fixture.assetId, 1_000)],
                asset: try Fixture.asset(),
                pools: [],
                reserves: [:]
            ),
            WalletCheck.unreadable(address: Fixture.wallet(2), gap: .requestFailed("timed out"))
        ]
        let reading = BalanceCombiner.combine(checks)
        #expect(reading.isComplete == false)
        #expect(reading.valueEvenIfShort?.combinedBalance == 1_000)
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
                asset: try Fixture.asset(),
                pools: [],
                reserves: [:]
            ),
            WalletCheck.unreadable(address: Fixture.wallet(2), gap: .notRead)
        ]
        let combined = try BalanceCombiner
            .combine(checks, storedBalances: [Fixture.wallet(2): 9_000_000])
            .requireComplete()
        #expect(combined.combinedBalance == 9_000_000)
        #expect(combined.walletsFromStoredBalances == [Fixture.wallet(2)])
    }

    @Test("A stored figure is never used for a pool position, because a pool moves with every trade")
    internal func storedFiguresDoNotCoverPools() throws {
        let pool = try Fixture.pool()
        let check = WalletCheck.read(
            address: Fixture.wallet(1),
            holdings: [Fixture.holding(Fixture.poolTokenId, 5)],
            asset: try Fixture.asset(),
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
        let pool = try Fixture.pool()
        let check = WalletCheck.read(
            address: Fixture.wallet(1),
            holdings: [Fixture.holding(Fixture.poolTokenId, 1)],
            asset: try Fixture.asset(),
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
        #expect(combined.liquidityAmount == 0)
        #expect(combined.hasLiquidity)
    }

    @Test("Adding up absurd balances gives an absurd number rather than taking the process down")
    internal func totalsSaturateRatherThanTrap() throws {
        let asset = try Fixture.asset()
        let checks = (0..<3).map { index in
            WalletCheck.read(
                address: Fixture.wallet(index),
                holdings: [Fixture.holding(Fixture.assetId, UInt64.max)],
                asset: asset,
                pools: [],
                reserves: [:]
            )
        }
        let combined = try BalanceCombiner.combine(checks).requireComplete()
        #expect(combined.combinedBalance == UInt64.max)
    }

    @Test("Nobody's wallets add up to nothing, completely")
    internal func noWalletsIsACompleteZero() throws {
        let combined = try BalanceCombiner.combine([]).requireComplete()
        #expect(combined.walletCount == 0)
        #expect(combined.combinedBalance == 0)
    }
}
