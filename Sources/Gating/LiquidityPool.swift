import Foundation

/// A pool the gated token is paired into, and what providing to it earns.
public struct LiquidityPool: Sendable, Equatable, Hashable, Identifiable {

    // MARK: - Properties

    /// Stable key. Persisted, and used to look a pool up.
    public let id: String

    /// What a member sees.
    public let name: String

    /// The asset id of the pool's own LP token.
    public let lpAssetId: UInt64

    /// The asset the gated token is paired with.
    public let pairedAssetId: UInt64

    /// Decimal places on the LP token.
    public let decimals: UInt8

    /// The role for holding any of this pool's LP token, or nil for none.
    public let roleId: String?

    /// The asset id this pool treats as the gated token.
    ///
    /// Carried per pool rather than read from a shared constant, and that is
    /// not redundancy. The original kept a global token id and, for a while,
    /// a second literal inside the pool table. When the two disagreed, the
    /// pooled side of a member's balance read as zero and every liquidity
    /// provider in the server was quietly demoted, which is the one failure
    /// ROLE-1.c exists to prevent. One answer, written once by the operator,
    /// copied into each pool at load.
    public let tokenAssetId: UInt64

    // MARK: - Initializers

    /// - Parameters:
    ///   - id: Stable key.
    ///   - name: What a member sees; the id when omitted.
    ///   - lpAssetId: The pool's own LP token.
    ///   - pairedAssetId: What the gated token is paired with.
    ///   - decimals: Decimal places on the LP token.
    ///   - roleId: The badge for providing to this pool.
    ///   - tokenAssetId: The gated token inside this pool.
    public init(
        id: String,
        name: String? = nil,
        lpAssetId: UInt64,
        pairedAssetId: UInt64,
        decimals: UInt8,
        roleId: String? = nil,
        tokenAssetId: UInt64
    ) {
        self.id = id
        self.name = name ?? id
        self.lpAssetId = lpAssetId
        self.pairedAssetId = pairedAssetId
        self.decimals = decimals
        self.roleId = roleId
        self.tokenAssetId = tokenAssetId
    }
}

/// What one member has in one pool, as somebody else worked it out.
///
/// Two figures, because they answer two questions. ``lpBaseUnits`` decides
/// whether the member is a provider at all; ``tokenBaseUnits`` is how much of
/// the gated token that position represents, and it is what counts toward the
/// holder ladder (ROLE-2). This layer does no pool arithmetic: the split
/// arrives already computed, which is what keeps the rules testable without a
/// chain.
public struct LiquidityPosition: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// Which pool.
    public let poolId: String

    /// How much of the pool's LP token the member holds.
    public let lpBaseUnits: UInt64

    /// How much of the gated token that position represents, in the token's
    /// smallest unit.
    public let tokenBaseUnits: UInt64

    // MARK: - Initializers

    /// - Parameters:
    ///   - poolId: Which pool.
    ///   - lpBaseUnits: How much of the pool's LP token is held.
    ///   - tokenBaseUnits: How much of the gated token that represents.
    public init(poolId: String, lpBaseUnits: UInt64, tokenBaseUnits: UInt64) {
        self.poolId = poolId
        self.lpBaseUnits = lpBaseUnits
        self.tokenBaseUnits = tokenBaseUnits
    }

    // MARK: - Public Methods

    /// True when the member holds any of this pool's LP token.
    public var isProviding: Bool { lpBaseUnits > 0 }
}

/// Every pool a server counts, and the one badge providing to any of them
/// earns.
public struct LiquidityPoolCatalog: Sendable, Equatable {

    // MARK: - Properties

    /// The pools, in the order they were configured.
    public let pools: [LiquidityPool]

    /// The badge for providing to any pool at all, or nil for none.
    public let providerRoleId: String?

    // MARK: - Initializers

    /// - Parameters:
    ///   - pools: Every pool the server counts.
    ///   - providerRoleId: The badge for providing to any of them.
    public init(pools: [LiquidityPool] = [], providerRoleId: String? = nil) {
        self.pools = pools
        self.providerRoleId = providerRoleId
    }

    // MARK: - Public Methods

    /// True when the server counts no pools.
    public var isEmpty: Bool { pools.isEmpty }

    /// The pool with this id, or nil.
    public func pool(id: String) -> LiquidityPool? {
        pools.first { $0.id == id }
    }

    /// The pool whose LP token this is, or nil.
    public func pool(lpAssetId: UInt64) -> LiquidityPool? {
        pools.first { $0.lpAssetId == lpAssetId }
    }

    /// Every role providing liquidity can grant.
    public var allRoleIds: Set<String> {
        var ids = Set(pools.compactMap(\.roleId))
        if let providerRoleId {
            ids.insert(providerRoleId)
        }
        return ids
    }
}
