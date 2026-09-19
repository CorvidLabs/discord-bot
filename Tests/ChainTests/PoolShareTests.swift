import Foundation
import Testing
@testable import Chain

/// What a holding of a pool's token is worth.
///
/// Whole numbers throughout. The version this replaces went through `Decimal`
/// and then a `Double` percentage, and the answers here are the same figures
/// without the round trip.
@Suite("What a pool position is worth")
internal struct PoolShareTests {

    // MARK: - The arithmetic

    @Test("A tenth of the pool tokens is a tenth of each side")
    internal func straightforwardShare() throws {
        let pool = try Fixture.pool()
        let share = Fixture.reserves(pool: pool).share(ofPoolTokens: 100_000)
        #expect(share.countedAssetAmount == 100_000_000)
        #expect(share.otherAssetAmount == 200_000)
        #expect(share.shareMillionths == 100_000)
        #expect(share.formattedSharePercent == "10.0000%")
    }

    @Test("A share that does not divide evenly rounds down, never up")
    internal func roundsDown() throws {
        let pool = try Fixture.pool()
        let reserves = Fixture.reserves(pool: pool, counted: 10, other: 10, circulating: 3)
        let share = reserves.share(ofPoolTokens: 1)
        // A third of ten is three and a bit. Showing four would be showing
        // somebody more than the pool could hand back.
        #expect(share.countedAssetAmount == 3)
        #expect(share.shareMillionths == 333_333)
    }

    @Test("A pool and a holding both near the largest number the chain can hold still divide")
    internal func hugeNumbersDoNotOverflow() throws {
        let pool = try Fixture.pool()
        let huge: UInt64 = 1_000_000_000_000_000_000
        let reserves = Fixture.reserves(
            pool: pool,
            counted: huge,
            other: huge,
            circulating: huge
        )
        // The obvious spelling multiplies these two together and wraps.
        let share = reserves.share(ofPoolTokens: huge / 2)
        #expect(share.countedAssetAmount == huge / 2)
        #expect(share.shareMillionths == 500_000)
    }

    @Test("A pool nobody has tokens in is worth nothing rather than dividing by zero")
    internal func emptyPool() throws {
        let pool = try Fixture.pool()
        let reserves = Fixture.reserves(pool: pool, circulating: 0)
        let share = reserves.share(ofPoolTokens: 10)
        #expect(share.countedAssetAmount == 0)
        #expect(share.shareMillionths == 0)
    }

    @Test("Holding more pool tokens than exist answers with the whole pool rather than trapping")
    internal func impossibleHoldingIsSurvivable() throws {
        let pool = try Fixture.pool()
        let reserves = Fixture.reserves(pool: pool, counted: 500, other: 40, circulating: 10)
        let share = reserves.share(ofPoolTokens: 50)
        #expect(share.countedAssetAmount == 500)
        #expect(share.otherAssetAmount == 40)
    }

    @Test("Which side counts is configuration, and the other side is reported separately")
    internal func countedSideIsConfigured() throws {
        let flipped = try LiquidityPool(
            id: "flipped",
            name: "PAIR / TOKEN",
            poolTokenId: Fixture.poolTokenId,
            poolTokenDecimals: 6,
            assetA: PoolSide(assetId: Fixture.pairedAssetId, symbol: "PAIR", decimals: 2),
            assetB: PoolSide(assetId: Fixture.assetId, symbol: "TOKEN", decimals: 6),
            countedAssetId: Fixture.assetId
        )
        let reserves = PoolReserves(
            pool: flipped,
            poolAddress: Fixture.poolAccount,
            assetABalance: 400,
            assetBBalance: 800,
            circulatingPoolTokens: 100,
            readAt: Date(timeIntervalSince1970: 0)
        )
        #expect(reserves.countedAssetBalance == 800)
        #expect(reserves.otherAssetBalance == 400)
        let share = reserves.share(ofPoolTokens: 25)
        #expect(share.countedAssetAmount == 200)
        #expect(share.otherAssetAmount == 100)
    }

    @Test("The two sides can have different precision, and neither is assumed")
    internal func sidesKeepTheirOwnPrecision() throws {
        let pool = try LiquidityPool(
            id: "mixed",
            name: "TOKEN / CENTS",
            poolTokenId: Fixture.poolTokenId,
            poolTokenDecimals: 6,
            assetA: PoolSide(assetId: Fixture.assetId, symbol: "TOKEN", decimals: 6),
            assetB: PoolSide(assetId: Fixture.pairedAssetId, symbol: "CENTS", decimals: 2),
            countedAssetId: Fixture.assetId
        )
        #expect(pool.countedSide.decimals == 6)
        #expect(pool.otherSide.decimals == 2)
        #expect(ChainFormatting.amount(150, decimals: Int(pool.otherSide.decimals)) == "1.5")
    }

    // MARK: - The helper underneath

    @Test("Dividing a total by a ratio is exact, or zero when there is nothing to divide")
    internal func exactRatioEdges() {
        #expect(ExactRatio.portion(of: 100, numerator: 1, denominator: 4) == 25)
        #expect(ExactRatio.portion(of: 100, numerator: 0, denominator: 4) == 0)
        #expect(ExactRatio.portion(of: 100, numerator: 1, denominator: 0) == 0)
        #expect(ExactRatio.portion(of: 0, numerator: 1, denominator: 4) == 0)
        #expect(ExactRatio.portion(of: UInt64.max, numerator: 1, denominator: 1) == UInt64.max)
    }
}
