import Foundation
import Gating

/// What a pool held when it was last read.
///
/// The two sides are named **counted** and **other** rather than A and B. They
/// were A and B while this module carried its own pool type, which said which
/// of the two positions the counted asset sat in; the pool an operator
/// actually writes down says which asset counts and which it is paired with,
/// and there is no third fact saying which came first. Keeping A and B would
/// have meant inventing an ordering, and every reader of it would have had to
/// look up which end the real answer was at.
public struct PoolReserves: Sendable, Equatable {

    // MARK: - Properties

    /// The pool this describes.
    public let pool: LiquidityPool

    /// The account holding the pool's reserves.
    public let poolAddress: String

    /// How much of the counted asset the pool holds, in its smallest unit.
    public let countedAssetBalance: UInt64

    /// How much of the other side the pool holds, in that asset's smallest
    /// unit.
    public let otherAssetBalance: UInt64

    /// Pool tokens in circulation, which is what a provider's holding is a
    /// share of.
    public let circulatingPoolTokens: UInt64

    /// When this was read, so a caller can say how stale it is.
    public let readAt: Date

    // MARK: - Initializers

    /// - Parameters:
    ///   - pool: The pool this describes.
    ///   - poolAddress: The account holding its reserves.
    ///   - countedAssetBalance: How much of the counted asset the pool holds.
    ///   - otherAssetBalance: How much of the other side it holds.
    ///   - circulatingPoolTokens: Pool tokens in somebody's hands.
    ///   - readAt: When this was read, passed in so a test pins it and a
    ///     caller can say how stale it is.
    public init(
        pool: LiquidityPool,
        poolAddress: String,
        countedAssetBalance: UInt64,
        otherAssetBalance: UInt64,
        circulatingPoolTokens: UInt64,
        readAt: Date
    ) {
        self.pool = pool
        self.poolAddress = poolAddress
        self.countedAssetBalance = countedAssetBalance
        self.otherAssetBalance = otherAssetBalance
        self.circulatingPoolTokens = circulatingPoolTokens
        self.readAt = readAt
    }

    // MARK: - Public Methods

    /// What a holding of this pool's token is worth of each side.
    ///
    /// Integer arithmetic throughout. The version this replaces went through
    /// `Decimal` for the amounts and `Double` for the percentage, which is one
    /// conversion more than the answer needs: a share is a ratio of two whole
    /// numbers of smallest units, and the exact answer is a whole number of
    /// smallest units. Rounded down, always, so a card never shows somebody
    /// more than the pool could actually give them back.
    ///
    /// - Parameter held: The pool tokens the provider holds.
    public func share(ofPoolTokens held: UInt64) -> PoolShare {
        guard circulatingPoolTokens > 0, held > 0 else {
            return PoolShare(
                poolId: pool.id,
                countedAssetId: pool.tokenAssetId,
                poolTokenBalance: held,
                circulatingPoolTokens: circulatingPoolTokens,
                shareMillionths: 0,
                countedAssetAmount: 0,
                otherAssetAmount: 0
            )
        }
        return PoolShare(
            poolId: pool.id,
            countedAssetId: pool.tokenAssetId,
            poolTokenBalance: held,
            circulatingPoolTokens: circulatingPoolTokens,
            shareMillionths: ExactRatio.portion(
                of: 1_000_000,
                numerator: held,
                denominator: circulatingPoolTokens
            ),
            countedAssetAmount: ExactRatio.portion(
                of: countedAssetBalance,
                numerator: held,
                denominator: circulatingPoolTokens
            ),
            otherAssetAmount: ExactRatio.portion(
                of: otherAssetBalance,
                numerator: held,
                denominator: circulatingPoolTokens
            )
        )
    }
}

/// What one provider's pool tokens are worth.
public struct PoolShare: Sendable, Equatable {

    // MARK: - Properties

    /// The pool this is a share of.
    public let poolId: String

    /// Which asset the counted amount is of.
    public let countedAssetId: UInt64

    /// The pool tokens held.
    public let poolTokenBalance: UInt64

    /// Pool tokens in circulation at the time.
    public let circulatingPoolTokens: UInt64

    /// The share of the pool, in millionths.
    ///
    /// Millionths rather than a percentage as a `Double`, so that what is
    /// printed is what was computed. A tenth of a basis point is enough
    /// precision for the smallest position worth showing.
    public let shareMillionths: UInt64

    /// The provider's part of the counted asset, in its smallest unit. This
    /// is the part that counts toward a member's balance.
    public let countedAssetAmount: UInt64

    /// The provider's part of the other side, in that asset's smallest unit.
    public let otherAssetAmount: UInt64

    // MARK: - Initializers

    /// Built by ``PoolReserves/share(ofPoolTokens:)``. Public so a host can
    /// rebuild one from figures it stored earlier.
    ///
    /// - Parameters:
    ///   - poolId: The pool this is a share of.
    ///   - countedAssetId: Which asset the counted amount is of.
    ///   - poolTokenBalance: The pool tokens held.
    ///   - circulatingPoolTokens: Pool tokens in circulation at the time.
    ///   - shareMillionths: The share of the pool, in millionths.
    ///   - countedAssetAmount: The provider's part of the counted asset.
    ///   - otherAssetAmount: The provider's part of the other side.
    public init(
        poolId: String,
        countedAssetId: UInt64,
        poolTokenBalance: UInt64,
        circulatingPoolTokens: UInt64,
        shareMillionths: UInt64,
        countedAssetAmount: UInt64,
        otherAssetAmount: UInt64
    ) {
        self.poolId = poolId
        self.countedAssetId = countedAssetId
        self.poolTokenBalance = poolTokenBalance
        self.circulatingPoolTokens = circulatingPoolTokens
        self.shareMillionths = shareMillionths
        self.countedAssetAmount = countedAssetAmount
        self.otherAssetAmount = otherAssetAmount
    }

    // MARK: - Public Methods

    /// The share as a percentage with four decimal places.
    public var formattedSharePercent: String {
        ChainFormatting.percent(millionths: shareMillionths)
    }
}

/// `total * numerator / denominator`, exactly, without overflowing on the way.
///
/// The obvious spelling of this multiplies two balances together and overflows
/// a 64 bit count long before either of them is unreasonable: a pool holding
/// ten to the fifteenth of each side, which is ordinary for a six decimal
/// asset, overflows against a holding of the same size. Full width
/// multiplication keeps the intermediate product intact and the division brings
/// it back into range.
internal enum ExactRatio: Sendable {

    /// - Parameters:
    ///   - total: The amount being divided up.
    ///   - numerator: The part held.
    ///   - denominator: The whole.
    /// - Returns: The portion, rounded down. Zero when the denominator is zero,
    ///   and the whole total when the numerator is at least the denominator,
    ///   because a quotient that does not fit would trap and a holding larger
    ///   than the supply is a bad reading rather than a reason to take the
    ///   process down.
    internal static func portion(of total: UInt64, numerator: UInt64, denominator: UInt64) -> UInt64 {
        guard denominator > 0, numerator > 0, total > 0 else { return 0 }
        guard numerator < denominator else { return total }
        let product = total.multipliedFullWidth(by: numerator)
        let (quotient, _) = denominator.dividingFullWidth(product)
        return quotient
    }
}
