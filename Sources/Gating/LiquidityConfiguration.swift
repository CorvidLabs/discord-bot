import Foundation

/// Builds a ``LiquidityPoolCatalog`` from numbered variables.
///
/// ```
/// POOL_1_ID=token_usd
/// POOL_1_NAME=TOKEN/USD
/// POOL_1_LP_ASA=...        # the pool's own LP token
/// POOL_1_PAIRED_ASA=...    # what the gated token is paired with
/// POOL_1_DECIMALS=6        # decimal places on the LP token
/// POOL_1_ROLE_ID=...       # providing to this pool earns this
/// LP_PROVIDER_ROLE_ID=...  # providing to any pool earns this
/// ```
///
/// The original shipped four pools written into the source with their asset
/// ids, and read each pool's roles from a variable whose name was built out
/// of the pool's id, so adding a fifth pool meant editing Swift. Pools are
/// numbered here like everything else, and the first gap ends the list.
///
/// A server that pairs its token nowhere sets none of this.
public enum LiquidityConfiguration: Sendable {

    // MARK: - Properties

    /// The variable naming the badge for providing to any pool.
    public static let providerRoleKey = "LP_PROVIDER_ROLE_ID"

    // MARK: - Public Methods

    /// Reads the catalogue from a dictionary. The shape tests use.
    public static func load(
        from environment: [String: String],
        token: TokenProfile
    ) throws -> LiquidityPoolCatalog {
        try load({ environment[$0] }, token: token)
    }

    /// Reads the catalogue, or says which variable is wrong.
    ///
    /// - Parameters:
    ///   - lookup: Reads one variable.
    ///   - token: The gated token. Each pool is given its asset id at load,
    ///     rather than reaching for a global at the moment it is needed. See
    ///     ``LiquidityPool/tokenAssetId`` for what happened when there were
    ///     two answers to that question.
    public static func load(
        _ lookup: (String) -> String?,
        token: TokenProfile
    ) throws -> LiquidityPoolCatalog {
        var pools: [LiquidityPool] = []
        var seenIds: [String: String] = [:]
        var seenLPAssets: [UInt64: String] = [:]

        for index in 1...NumberedEnvironment.maxEntries {
            let prefix = "POOL_\(index)_"
            let idKey = "\(prefix)ID"
            guard let rawId = NumberedEnvironment.nonEmpty(idKey, lookup) else { break }
            guard let id = NumberedEnvironment.slug(rawId) else {
                throw GatingConfigurationError.unusableName(key: idKey, value: rawId)
            }
            if let first = seenIds[id] {
                throw GatingConfigurationError.duplicateId(id: id, first: first, second: idKey)
            }
            seenIds[id] = idKey

            let lpKey = "\(prefix)LP_ASA"
            let lpAssetId = try NumberedEnvironment.requiredWholeNumber(
                lpKey,
                purpose: "It is the asset id of pool \(index)'s own LP token, which is what a "
                    + "member holds to prove they provided to it.",
                lookup
            )
            if let first = seenLPAssets[lpAssetId] {
                throw GatingConfigurationError.duplicateAsset(
                    assetId: lpAssetId,
                    first: first,
                    second: lpKey
                )
            }
            seenLPAssets[lpAssetId] = lpKey

            // Both sides are required. The original let either be absent and
            // then skipped any pool missing one, which meant a half-written
            // pool counted for nothing and said nothing. A pool whose pair is
            // unknown cannot be priced, so it is refused at load instead.
            let pairedAssetId = try NumberedEnvironment.requiredWholeNumber(
                "\(prefix)PAIRED_ASA",
                purpose: "It is the asset your token is paired with in pool \(index). Without "
                    + "it, nothing can work out how much of your token a position holds.",
                lookup
            )
            let decimalsKey = "\(prefix)DECIMALS"
            let decimals = try NumberedEnvironment.requiredWholeNumber(
                decimalsKey,
                purpose: "It is how many decimal places pool \(index)'s LP token has.",
                lookup
            )
            guard decimals <= 19 else {
                throw GatingConfigurationError.unsupportedDecimals(key: decimalsKey, value: decimals)
            }

            pools.append(
                LiquidityPool(
                    id: id,
                    name: NumberedEnvironment.nonEmpty("\(prefix)NAME", lookup),
                    lpAssetId: lpAssetId,
                    pairedAssetId: pairedAssetId,
                    decimals: UInt8(decimals),
                    roleId: NumberedEnvironment.nonEmpty("\(prefix)ROLE_ID", lookup),
                    tokenAssetId: token.assetId
                )
            )
        }

        if pools.count == NumberedEnvironment.maxEntries {
            try NumberedEnvironment.refuseOverflow("POOL_\(NumberedEnvironment.maxEntries + 1)_ID", lookup)
        }
        return LiquidityPoolCatalog(
            pools: pools,
            providerRoleId: NumberedEnvironment.nonEmpty(providerRoleKey, lookup)
        )
    }
}
