import Foundation

/// Everything an operator decides about what holding something earns.
///
/// One value, loaded once, and the only thing the rules read. Nothing in this
/// module reaches for a global, a literal asset id, a literal role or a
/// default ladder, because every one of those is a sentence from somebody
/// else's project appearing in a stranger's server (ADOPT-1.c).
public struct GatingConfiguration: Sendable, Equatable {

    // MARK: - Properties

    /// The token the ladder is measured in.
    public let token: TokenProfile

    /// The rungs.
    public let ladder: TierLadder

    /// Discord role id per rung id.
    public let tierRoleIds: [String: String]

    /// Every collection the server gates on.
    public let collections: CollectionCatalog

    /// Every pool the server counts.
    public let pools: LiquidityPoolCatalog

    /// The role for having verified an account at all, or nil for none.
    public let verifiedRoleId: String?

    /// The accounts allowed to administer. Empty by default; see
    /// ``AdminAllowlist``.
    public let admins: AdminAllowlist

    // MARK: - Initializers

    /// - Parameters:
    ///   - token: The token the ladder is measured in.
    ///   - tiers: The ladder and its roles.
    ///   - collections: Collections the server gates on.
    ///   - pools: Pools the server counts.
    ///   - verifiedRoleId: The role for having verified at all.
    ///   - admins: Accounts allowed to administer.
    public init(
        token: TokenProfile,
        tiers: LoadedTiers,
        collections: CollectionCatalog = CollectionCatalog(),
        pools: LiquidityPoolCatalog = LiquidityPoolCatalog(),
        verifiedRoleId: String? = nil,
        admins: AdminAllowlist = AdminAllowlist()
    ) {
        self.token = token
        self.ladder = tiers.ladder
        self.tierRoleIds = tiers.roleIds
        self.collections = collections
        self.pools = pools
        self.verifiedRoleId = verifiedRoleId
        self.admins = admins
    }

    // MARK: - Public Methods

    /// The Discord role a rung grants, or nil when it grants none.
    public func roleId(for tier: Tier) -> String? {
        tierRoleIds[tier.id]
    }

    /// Every role this configuration can grant.
    ///
    /// The bot adds and removes these and nothing else. A role that is not in
    /// here is somebody else's, and a sweep that touched one would be taking
    /// away a badge a moderator handed out by hand.
    public var allRoleIds: Set<String> {
        var ids = Set(tierRoleIds.values)
        ids.formUnion(collections.allRoleIds)
        ids.formUnion(pools.allRoleIds)
        if let verifiedRoleId {
            ids.insert(verifiedRoleId)
        }
        return ids
    }
}

extension GatingConfiguration {

    // MARK: - Loading

    /// The variable naming the role for having verified an account.
    public static let verifiedRoleKey = "VERIFIED_ROLE_ID"

    /// Reads the whole configuration from a dictionary. The shape tests use.
    public static func load(from environment: [String: String]) throws -> GatingConfiguration {
        try load { environment[$0] }
    }

    /// Reads the whole configuration, or says which variable is wrong.
    ///
    /// The token is read first because the ladder's thresholds cannot be
    /// converted without its decimals, and the pools cannot be given an asset
    /// id without its asset id. Getting the order wrong is how a module ends
    /// up assuming six decimals in nine places.
    public static func load(_ lookup: (String) -> String?) throws -> GatingConfiguration {
        let token = try TokenProfile.load(lookup)
        return GatingConfiguration(
            token: token,
            tiers: try TierConfiguration.load(lookup, token: token),
            collections: try CollectionConfiguration.load(lookup),
            pools: try LiquidityConfiguration.load(lookup, token: token),
            verifiedRoleId: NumberedEnvironment.nonEmpty(verifiedRoleKey, lookup),
            admins: try AdminAllowlist.load(lookup)
        )
    }
}
