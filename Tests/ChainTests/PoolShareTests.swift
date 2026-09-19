import Foundation
import Gating
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
        let pool = Fixture.pool()
        let share = Fixture.reserves(pool: pool).share(ofPoolTokens: 100_000)
        #expect(share.countedAssetAmount == 100_000_000)
        #expect(share.otherAssetAmount == 200_000)
        #expect(share.shareMillionths == 100_000)
        #expect(share.formattedSharePercent == "10.0000%")
    }

    @Test("A share that does not divide evenly rounds down, never up")
    internal func roundsDown() throws {
        let pool = Fixture.pool()
        let reserves = Fixture.reserves(pool: pool, counted: 10, other: 10, circulating: 3)
        let share = reserves.share(ofPoolTokens: 1)
        // A third of ten is three and a bit. Showing four would be showing
        // somebody more than the pool could hand back.
        #expect(share.countedAssetAmount == 3)
        #expect(share.shareMillionths == 333_333)
    }

    @Test("A pool and a holding both near the largest number the chain can hold still divide")
    internal func hugeNumbersDoNotOverflow() throws {
        let pool = Fixture.pool()
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
        let pool = Fixture.pool()
        let reserves = Fixture.reserves(pool: pool, circulating: 0)
        let share = reserves.share(ofPoolTokens: 10)
        #expect(share.countedAssetAmount == 0)
        #expect(share.shareMillionths == 0)
    }

    @Test("Holding more pool tokens than exist answers with the whole pool rather than trapping")
    internal func impossibleHoldingIsSurvivable() throws {
        let pool = Fixture.pool()
        let reserves = Fixture.reserves(pool: pool, counted: 500, other: 40, circulating: 10)
        let share = reserves.share(ofPoolTokens: 50)
        #expect(share.countedAssetAmount == 500)
        #expect(share.otherAssetAmount == 40)
    }

    @Test("Which asset counts comes from the pool, and the other side is reported separately")
    internal func countedSideIsConfigured() {
        // The pool an operator writes down says which asset counts and which
        // it is paired with. There is no A and B to get the wrong way round,
        // which is the point: the pool type this module used to carry had an
        // ordering nothing in the configuration could set.
        let reserves = PoolReserves(
            pool: Fixture.pool(id: "flipped"),
            poolAddress: Fixture.poolAccount,
            countedAssetBalance: 800,
            otherAssetBalance: 400,
            circulatingPoolTokens: 100,
            readAt: Date(timeIntervalSince1970: 0)
        )
        #expect(reserves.countedAssetBalance == 800)
        #expect(reserves.otherAssetBalance == 400)
        let share = reserves.share(ofPoolTokens: 25)
        #expect(share.countedAssetAmount == 200)
        #expect(share.otherAssetAmount == 100)
        #expect(share.countedAssetId == Fixture.assetId)
    }

    @Test("The amounts are smallest units, so the token's own precision prints them")
    internal func amountsArePrintedAtTheTokenPrecision() throws {
        // The pool used to carry a symbol and a decimal count per side, and
        // no file in this module ever read either: what a card shows comes
        // from the one `TokenProfile` the operator configured, and the other
        // side's precision is a number nothing here has been given a way to
        // learn. Inventing one is worse than not printing it.
        let reserves = Fixture.reserves(
            pool: Fixture.pool(),
            counted: 1_500,
            other: 1_500,
            circulating: 1_000
        )
        let share = reserves.share(ofPoolTokens: 100)
        #expect(share.countedAssetAmount == 150)
        #expect(try Fixture.token(decimals: 2).format(share.countedAssetAmount) == "1.5")
        #expect(try Fixture.token(decimals: 6).format(share.countedAssetAmount) == "0.00015")
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
