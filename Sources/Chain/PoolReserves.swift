import Foundation

/// What a pool held when it was last read.
public struct PoolReserves: Sendable, Equatable {

    // MARK: - Properties

    /// The pool this describes.
    public let pool: LiquidityPool

    /// The account holding the pool's reserves.
    public let poolAddress: String

    /// How much of side A the pool holds, in that asset's smallest unit.
    public let assetABalance: UInt64

    /// How much of side B the pool holds, in that asset's smallest unit.
    public let assetBBalance: UInt64

    /// Pool tokens in circulation, which is what a provider's holding is a
    /// share of.
    public let circulatingPoolTokens: UInt64

    /// When this was read, so a caller can say how stale it is.
    public let readAt: Date

    // MARK: - Initializers

    /// - Parameter readAt: When this was read, passed in so a test pins it
    ///   and a caller can say how stale it is.
    public init(
        pool: LiquidityPool,
        poolAddress: String,
        assetABalance: UInt64,
        assetBBalance: UInt64,
        circulatingPoolTokens: UInt64,
        readAt: Date
    ) {
        self.pool = pool
        self.poolAddress = poolAddress
        self.assetABalance = assetABalance
        self.assetBBalance = assetBBalance
        self.circulatingPoolTokens = circulatingPoolTokens
        self.readAt = readAt
    }

    // MARK: - Public Methods

    /// How much of the counted asset the pool holds.
    public var countedAssetBalance: UInt64 {
        pool.assetA.assetId == pool.countedAssetId ? assetABalance : assetBBalance
    }

    /// How much of the other side the pool holds.
    public var otherAssetBalance: UInt64 {
        pool.assetA.assetId == pool.countedAssetId ? assetBBalance : assetABalance
    }

    /// What a holding of this pool's token is worth of each side.
    ///
    /// Integer arithmetic throughout. The version this replaces went through
    /// `Decimal` for the amounts and `Double` for the percentage, which is one
    /// conversion more than the answer needs: a share is a ratio of two whole
    /// numbers of smallest units, and the exact answer is a whole number of
    /// smallest units. Rounded down, always, so a card never shows somebody
    /// more than the pool could actually give them back.
    public func share(ofPoolTokens held: UInt64) -> PoolShare {
        guard circulatingPoolTokens > 0, held > 0 else {
            return PoolShare(
                poolId: pool.id,
                countedAssetId: pool.countedAssetId,
                assetAId: pool.assetA.assetId,
                poolTokenBalance: held,
                circulatingPoolTokens: circulatingPoolTokens,
                shareMillionths: 0,
                assetAAmount: 0,
                assetBAmount: 0
            )
        }
        return PoolShare(
            poolId: pool.id,
            countedAssetId: pool.countedAssetId,
            assetAId: pool.assetA.assetId,
            poolTokenBalance: held,
            circulatingPoolTokens: circulatingPoolTokens,
            shareMillionths: ExactRatio.portion(
                of: 1_000_000,
                numerator: held,
                denominator: circulatingPoolTokens
            ),
            assetAAmount: ExactRatio.portion(
                of: assetABalance,
                numerator: held,
                denominator: circulatingPoolTokens
            ),
            assetBAmount: ExactRatio.portion(
                of: assetBBalance,
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

    /// Which side counts toward a member's balance.
    public let countedAssetId: UInt64

    /// Side A's asset id, so the amounts below can be told apart.
    public let assetAId: UInt64

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

    /// The provider's part of side A, in that asset's smallest unit.
    public let assetAAmount: UInt64

    /// The provider's part of side B, in that asset's smallest unit.
    public let assetBAmount: UInt64

    // MARK: - Initializers

    /// Built by ``PoolReserves/share(ofPoolTokens:)``. Public so a host can
    /// rebuild one from figures it stored earlier.
    public init(
        poolId: String,
        countedAssetId: UInt64,
        assetAId: UInt64,
        poolTokenBalance: UInt64,
        circulatingPoolTokens: UInt64,
        shareMillionths: UInt64,
        assetAAmount: UInt64,
        assetBAmount: UInt64
    ) {
        self.poolId = poolId
        self.countedAssetId = countedAssetId
        self.assetAId = assetAId
        self.poolTokenBalance = poolTokenBalance
        self.circulatingPoolTokens = circulatingPoolTokens
        self.shareMillionths = shareMillionths
        self.assetAAmount = assetAAmount
        self.assetBAmount = assetBAmount
    }

    // MARK: - Public Methods

    /// The part that counts toward a member's balance.
    public var countedAssetAmount: UInt64 {
        assetAId == countedAssetId ? assetAAmount : assetBAmount
    }

    /// The part that does not.
    public var otherAssetAmount: UInt64 {
        assetAId == countedAssetId ? assetBAmount : assetAAmount
    }

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
