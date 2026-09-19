import Foundation

/// One side of a pool's pair.
public struct PoolSide: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The asset's on chain id. Zero names the chain's own currency, which is
    /// held as an account balance rather than as an asset.
    public let assetId: UInt64

    /// What to call it on a card.
    public let symbol: String

    /// Its decimal places. Configuration, never assumed: the two sides of a
    /// pair routinely have different precision, and guessing six for both
    /// misreports one of them.
    public let decimals: UInt8

    // MARK: - Initializers

    /// - Parameter assetId: Zero for the chain's own currency.
    public init(assetId: UInt64, symbol: String, decimals: UInt8) {
        self.assetId = assetId
        self.symbol = symbol
        self.decimals = decimals
    }

    // MARK: - Public Methods

    /// Whether this side is the chain's own currency rather than an asset.
    public var isNativeCurrency: Bool { assetId == 0 }
}

/// A liquidity pool an operator wants counted.
///
/// What somebody has parked in a pool has not stopped being theirs, and a
/// community that treats a provider as having sold up is punishing them for
/// helping. Counting a pool means turning a holding of its pool token into an
/// amount of the counted asset, which takes the pool's reserves.
///
/// Every id here is configuration with no default. The bot this was ported
/// from shipped a file of pool ids belonging to one project; an operator who
/// left it alone would have counted somebody else's pools.
public struct LiquidityPool: Sendable, Equatable, Hashable, Identifiable {

    // MARK: - Properties

    /// How this pool is referred to in configuration and in a record.
    public let id: String

    /// What to call it on a card.
    public let name: String

    /// The asset id of the pool's own token, the thing a provider holds.
    public let poolTokenId: UInt64

    /// The pool token's decimal places.
    public let poolTokenDecimals: UInt8

    /// One side of the pair.
    public let assetA: PoolSide

    /// The other side of the pair.
    public let assetB: PoolSide

    /// Which side counts toward a member's balance. Has to be one of the two.
    public let countedAssetId: UInt64

    // MARK: - Initializers

    /// - Parameters:
    ///   - id: Unique among the configured pools.
    ///   - name: What to call it on a card.
    ///   - poolTokenId: The pool's own token. Refused when zero, because the
    ///     chain's own currency is not a pool token and a zero here is an
    ///     unset variable.
    ///   - poolTokenDecimals: The pool token's decimal places.
    ///   - assetA: One side of the pair.
    ///   - assetB: The other side.
    ///   - countedAssetId: Which side counts. Refused when it is neither,
    ///     because nothing would ever be counted and the mistake would show up
    ///     as members quietly missing a tier.
    public init(
        id: String,
        name: String,
        poolTokenId: UInt64,
        poolTokenDecimals: UInt8,
        assetA: PoolSide,
        assetB: PoolSide,
        countedAssetId: UInt64
    ) throws {
        guard poolTokenId > 0 else {
            throw ChainConfigurationError.invalidValue(
                variable: "pool `\(id)` pool token id",
                value: "0",
                expected: "the asset id of the pool's own token"
            )
        }
        guard countedAssetId == assetA.assetId || countedAssetId == assetB.assetId else {
            throw ChainConfigurationError.poolCountsAnAssetItDoesNotHold(poolId: id, assetId: countedAssetId)
        }
        self.id = id
        self.name = name
        self.poolTokenId = poolTokenId
        self.poolTokenDecimals = poolTokenDecimals
        self.assetA = assetA
        self.assetB = assetB
        self.countedAssetId = countedAssetId
    }

    // MARK: - Public Methods

    /// The side that counts toward a member's balance.
    public var countedSide: PoolSide {
        assetA.assetId == countedAssetId ? assetA : assetB
    }

    /// The side that does not.
    public var otherSide: PoolSide {
        assetA.assetId == countedAssetId ? assetB : assetA
    }

    /// Refuses a set of pools that would silently drop one of its members.
    ///
    /// Two pools sharing an id is not a small mistake: the second overwrites
    /// the first everywhere a pool is looked up by id, and the pool that
    /// vanishes takes its providers' balances with it.
    public static func validate(_ pools: [LiquidityPool]) throws {
        var seen: Set<String> = []
        for pool in pools where !seen.insert(pool.id).inserted {
            throw ChainConfigurationError.duplicatePoolId(pool.id)
        }
    }
}
